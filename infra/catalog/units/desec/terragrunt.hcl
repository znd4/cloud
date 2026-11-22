# Unit: the deSEC zone for ACME challenges and the homelab Caddy token.

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/infra/catalog/modules/desec"
}

inputs = {
  zone       = values.acme_zone
  token_name = values.token_name
}
