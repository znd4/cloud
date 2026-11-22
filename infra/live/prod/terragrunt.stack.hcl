# Production DNS: the DNSimple domains and the deSEC ACME zone.
#
#   terragrunt stack generate      # writes .terragrunt-stack/ (not in git)
#   terragrunt stack run plan
#
# infra/README.md has the credentials and the first-run steps.

locals {
  acme_zone = "acme.znd4.dev"
}

unit "desec" {
  source = "../../catalog/units/desec"
  path   = "desec"
  values = {
    acme_zone  = local.acme_zone
    token_name = "hl01-acme"
  }
}

unit "dnsimple" {
  source = "../../catalog/units/dnsimple"
  path   = "dnsimple"
  values = {
    acme_zone  = local.acme_zone
    desec_path = "../desec"
  }
}
