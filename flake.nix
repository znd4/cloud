{
  description = "znd4/cloud: DNS and other cloud infrastructure";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          f (
            import nixpkgs {
              inherit system;
              # The 1Password CLI is unfree.
              config.allowUnfreePredicate = pkg: nixpkgs.lib.getName pkg == "1password-cli";
            }
          )
        );
    in
    {
      packages = forAllSystems (pkgs: {
        # Copy the 1Password service account token into the GitHub environment
        # secret that CI reads. The token goes from op to gh through a pipe and
        # is never printed.
        #
        #   nix run .#set-ci-token                 # default item
        #   nix run .#set-ci-token -- <item>       # item name or ID in the vault
        #
        # Environment overrides: CI_TOKEN_VAULT, CI_TOKEN_REPO, CI_TOKEN_ENV.
        set-ci-token = pkgs.writeShellApplication {
          name = "set-ci-token";
          runtimeInputs = [ pkgs._1password-cli ];
          text = ''
            # Prefer the caller's gh: it may get its login from a wrapper, such as
            # `op plugin run -- gh`. Use the nixpkgs gh only if none is on PATH.
            export PATH="$PATH:${pkgs.gh}/bin"

            case "''${1:-}" in
              -*)
                echo "usage: set-ci-token [item name or ID]" >&2
                exit 2
                ;;
            esac

            # 1Password names the item after the service account. op:// references
            # reject the ":" in that name, so this uses `op item get` instead.
            item="''${1:-Service Account Auth Token: cloud-ci}"
            vault="''${CI_TOKEN_VAULT:-Cloud CI}"
            repo="''${CI_TOKEN_REPO:-znd4/cloud}"
            env="''${CI_TOKEN_ENV:-cloud-ci}"

            echo "Setting OP_SERVICE_ACCOUNT_TOKEN in $repo (environment $env) from \"$item\" in vault \"$vault\"." >&2
            op item get "$item" --vault "$vault" --fields credential --reveal \
              | tr -d '\n' \
              | gh secret set OP_SERVICE_ACCOUNT_TOKEN --repo "$repo" --env "$env"
          '';
        };

        # Save a secret as the `credential` field of an API Credential item in
        # the Cloud CI vault. Creates the item, or replaces its credential if the
        # item exists. The value is never printed and never appears in a
        # command line.
        #
        #   nix run .#put-secret -- desec           # reads the clipboard (macOS), then clears it
        #   pbpaste | nix run .#put-secret -- desec # reads standard input
        #
        # Environment override: SECRET_VAULT.
        put-secret =
          pkgs.writers.writePython3Bin "put-secret"
            {
              makeWrapperArgs = [
                "--prefix"
                "PATH"
                ":"
                (pkgs.lib.makeBinPath [ pkgs._1password-cli ])
              ];
              flakeIgnore = [ "E501" ];
            }
            ''
              import json
              import os
              import shutil
              import subprocess
              import sys


              def op(*args, stdin=None):
                  """Run op. Pass secrets only through stdin, never as arguments."""
                  result = subprocess.run(
                      ["op", *args], input=stdin, capture_output=True, text=True
                  )
                  if result.returncode != 0:
                      sys.exit(f"op {args[0]} {args[1]} failed: {result.stderr.strip()}")
                  return result.stdout


              def main():
                  if len(sys.argv) != 2 or sys.argv[1].startswith("-") or ":" in sys.argv[1]:
                      sys.exit("usage: put-secret <item title>   (no ':' in the title, so op:// references work)")
                  title = sys.argv[1]
                  vault = os.environ.get("SECRET_VAULT", "Cloud CI")

                  from_clipboard = sys.stdin.isatty()
                  if from_clipboard:
                      if not shutil.which("pbpaste"):
                          sys.exit("put-secret: pipe the secret into standard input.")
                      value = subprocess.run(["pbpaste"], capture_output=True, text=True).stdout
                  else:
                      value = sys.stdin.read()
                  value = value.rstrip("\r\n")
                  if not value:
                      sys.exit("put-secret: the secret is empty.")

                  # Create the item only if op says that it does not exist. Any other
                  # error (app locked, two items with this title) stops the script,
                  # so a failure never makes a duplicate item.
                  check = subprocess.run(
                      ["op", "item", "get", title, "--vault", vault],
                      capture_output=True,
                      text=True,
                  )
                  if check.returncode == 0:
                      exists = True
                  elif "isn't an item" in check.stderr:
                      exists = False
                  else:
                      sys.exit(f"put-secret: cannot check for the item: {check.stderr.strip()}")
                  if exists:
                      item = json.loads(
                          op("item", "get", title, "--vault", vault, "--reveal", "--format", "json")
                      )
                      for field in item["fields"]:
                          if field["id"] == "credential":
                              field["value"] = value
                      op("item", "edit", title, "--vault", vault, stdin=json.dumps(item))
                      action = "Updated"
                  else:
                      item = {
                          "title": title,
                          "category": "API_CREDENTIAL",
                          "fields": [{"id": "credential", "type": "CONCEALED", "value": value}],
                      }
                      op("item", "create", "--vault", vault, "-", stdin=json.dumps(item))
                      action = "Created"

                  if from_clipboard:
                      subprocess.run(["pbcopy"], input="", text=True)
                  ref = f"op://{vault}/{title}/credential"
                  op("read", ref)
                  print(f"{action} {ref}", file=sys.stderr)


              main()
            '';
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs._1password-cli
            pkgs.gh
            # infra/: Terragrunt stack. OpenTofu 1.13 or later for
            # `tofu providers lock -oci-mirror`.
            pkgs.opentofu
            pkgs.terragrunt
          ];
        };
      });
    };
}
