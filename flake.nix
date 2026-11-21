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
          runtimeInputs = [
            pkgs._1password-cli
            pkgs.gh
          ];
          text = ''
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
            gh secret list --repo "$repo" --env "$env"
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
