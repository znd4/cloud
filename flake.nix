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
        put-secret = pkgs.writeShellApplication {
          name = "put-secret";
          runtimeInputs = [
            pkgs._1password-cli
            pkgs.jq
          ];
          text = ''
            title="''${1:-}"
            case "$title" in
              "" | -* | *:*)
                echo "usage: put-secret <item title>   (no ':' in the title, so op:// references work)" >&2
                exit 2
                ;;
            esac
            vault="''${SECRET_VAULT:-Cloud CI}"

            from_clipboard=false
            if [ -t 0 ]; then
              if ! command -v pbpaste >/dev/null; then
                echo "put-secret: pipe the secret into standard input." >&2
                exit 2
              fi
              value="$(pbpaste)"
              from_clipboard=true
            else
              value="$(cat)"
            fi
            # Drop a trailing newline or carriage return from the clipboard or a pipe.
            value="''${value%$'\n'}"
            value="''${value%$'\r'}"
            if [ -z "$value" ]; then
              echo "put-secret: the secret is empty." >&2
              exit 1
            fi

            # printf is a shell builtin, so the value does not appear in a command line.
            if op item get "$title" --vault "$vault" >/dev/null 2>&1; then
              { op item get "$title" --vault "$vault" --reveal --format json
                printf '%s' "$value" | jq -Rs .
              } | jq -s '.[1] as $v | .[0] | (.fields[] | select(.id == "credential") | .value) = $v' \
                | op item edit "$title" --vault "$vault" >/dev/null
              action=Updated
            else
              printf '%s' "$value" \
                | jq -Rs --arg title "$title" \
                  '{title: $title, category: "API_CREDENTIAL", fields: [{id: "credential", type: "CONCEALED", value: .}]}' \
                | op item create --vault "$vault" - >/dev/null
              action=Created
            fi
            unset value

            if [ "$from_clipboard" = true ]; then
              pbcopy </dev/null
            fi
            op read "op://$vault/$title/credential" >/dev/null
            echo "$action op://$vault/$title/credential" >&2
          '';
        };
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs._1password-cli
            pkgs.gh
          ];
        };
      });
    };
}
