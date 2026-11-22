# Shared Terragrunt config. Every unit includes it.
#
# - CLI config: infra/tofu.tfrc installs the znd4/* providers from the ghcr.io
#   OCI mirror. Terragrunt sets TF_CLI_CONFIG_FILE for every tofu command, so
#   local runs and CI use the same file.
# - Credentials: each provider reads them from the environment. See
#   infra/README.md.
# - State: encrypted with a passphrase (TF_VAR_state_passphrase). The backend
#   is "local" by default. CLOUD_TOFU_BACKEND=s3 selects the R2 bucket.

locals {
  backend = get_env("CLOUD_TOFU_BACKEND", "local")
  # State path per unit, without the generated `.terragrunt-stack/` part.
  state_key = replace(path_relative_to_include(), ".terragrunt-stack/", "")

  backend_configs = {
    local = {
      path = "${get_parent_terragrunt_dir()}/.state/${local.state_key}/tofu.tfstate"
    }
    # Cloudflare R2 through the S3 backend, as in znd4/homelab decision 0005.
    s3 = {
      # TODO(tofu-backend): make the bucket, then set the name and account ID.
      bucket       = "znd4-cloud-tofu"
      key          = "${local.state_key}/tofu.tfstate"
      region       = "auto"
      endpoints    = { s3 = "https://ACCOUNT_ID.r2.cloudflarestorage.com" }
      use_lockfile = true

      use_path_style              = true
      skip_credentials_validation = true
      skip_region_validation      = true
      skip_requesting_account_id  = true
      skip_s3_checksum            = true
      skip_metadata_api_check     = true

      # Terragrunt-only keys: do not try to make or change the bucket with AWS APIs.
      disable_bucket_update  = true
      skip_bucket_versioning = true
    }
  }
}

terraform {
  extra_arguments "cli_config" {
    commands = [
      "init", "plan", "apply", "destroy", "refresh", "import", "validate",
      "providers", "output", "show", "state", "console", "force-unlock", "test",
    ]
    env_vars = {
      TF_CLI_CONFIG_FILE = "${get_parent_terragrunt_dir()}/tofu.tfrc"
    }
  }
}

remote_state {
  backend = local.backend
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = local.backend_configs[local.backend]
}

generate "encryption" {
  path      = "encryption.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    variable "state_passphrase" {
      description = "Passphrase for OpenTofu state and plan encryption. Set TF_VAR_state_passphrase."
      type        = string
      sensitive   = true
    }

    terraform {
      encryption {
        key_provider "pbkdf2" "main" {
          passphrase = var.state_passphrase
        }
        method "aes_gcm" "main" {
          keys = key_provider.pbkdf2.main
        }
        state {
          method   = method.aes_gcm.main
          enforced = true
        }
        plan {
          method   = method.aes_gcm.main
          enforced = true
        }
      }
    }
  EOF
}
