# Unit: the DNSimple domains znd4.dev and znd4.me.
#
# The data is here, not in the stack file, because it is long. The stack sets
# only the wiring.

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/infra/catalog/modules/dnsimple"
}

# The NS records delegate acme.znd4.dev to deSEC. Make the zone at deSEC
# first, so the delegation never points at servers that do not serve it.
dependencies {
  paths = [values.desec_path]
}

inputs = {
  protonmail = {
    "znd4.dev" = {
      verification = "\"protonmail-verification=f425a51143cba67038b420d2012840c02db726c3\""
      dkim         = "dgwsf7fj6my2r3gc3nmtvkfmamr5klvflmeb4kdfe6ojl2asgwula"
    }
    "znd4.me" = {
      verification = "\"protonmail-verification=bf0b2c0048c78ef0584a1a8fc2cd3cf13828fd3a\""
      dkim         = "dspg66b3xa4h6ddxwhskf5bbduujpap6l6f7dktkxrrs624p7k34a"
    }
  }

  # znd4/cloud#5: delegate the ACME challenge zone to deSEC (homelab
  # decision 0003). These records are new.
  records = {
    "znd4.dev acme-ns1" = { zone = "znd4.dev", name = "acme", type = "NS", value = "ns1.desec.io" }
    "znd4.dev acme-ns2" = { zone = "znd4.dev", name = "acme", type = "NS", value = "ns2.desec.org" }
    "znd4.dev _acme-challenge.home" = {
      zone  = "znd4.dev"
      name  = "_acme-challenge.home"
      type  = "CNAME"
      value = "_acme-challenge.${values.acme_zone}"
    }
  }

  # Records that the Pulumi program made. IDs from the DNSimple API
  # (GET /v2/<account>/zones/<zone>/records), 2026-11-22.
  import_record_ids = {
    "znd4.dev protonmail-verification" = 56267037
    "znd4.dev mx-mail"                 = 56267033
    "znd4.dev mx-mailsec"              = 56267032
    "znd4.dev spf"                     = 56267023
    "znd4.dev dkim1"                   = 56267024
    "znd4.dev dkim2"                   = 56267030
    "znd4.dev dkim3"                   = 56267035
    "znd4.dev dmarc"                   = 56267029

    "znd4.me protonmail-verification" = 56267027
    "znd4.me mx-mail"                 = 56267036
    "znd4.me mx-mailsec"              = 56267034
    "znd4.me spf"                     = 56267031
    "znd4.me dkim1"                   = 56267028
    "znd4.me dkim2"                   = 56267026
    "znd4.me dkim3"                   = 56267038
    "znd4.me dmarc"                   = 56267025
  }
}
