# DNSimple domains and zone records. This replaces the Pulumi program in
# dnsimple/ (stack dns/dns): the same domains and the same Proton Mail records.
#
# The provider reads DNSIMPLE_TOKEN and DNSIMPLE_ACCOUNT from the environment.

terraform {
  required_version = ">= 1.13.0"
  required_providers {
    dnsimple = {
      source  = "dnsimple/dnsimple"
      version = "~> 2.2"
    }
  }
}

provider "dnsimple" {}

variable "protonmail" {
  description = <<-EOT
    Proton Mail settings per domain. Each domain gets the 8 records from the
    Proton Mail setup page: verification TXT, two MX, SPF, three DKIM CNAMEs
    and DMARC. dkim is the domain ID in the DKIM targets
    (protonmail.domainkey.<dkim>.domains.proton.ch).
  EOT
  type = map(object({
    verification = string
    dkim         = string
    dmarc        = optional(string, "\"v=DMARC1; p=quarantine\"")
  }))
}

variable "records" {
  description = "Other zone records, by a stable key. name is \"\" at the zone apex."
  type = map(object({
    zone     = string
    name     = string
    type     = string
    value    = string
    ttl      = optional(number, 3600)
    priority = optional(number)
  }))
  default = {}
}

variable "import_record_ids" {
  description = <<-EOT
    DNSimple record IDs of records that already exist, by record key. OpenTofu
    imports them instead of creating them. After the import, the entries do
    nothing, and you can remove them.
  EOT
  type        = map(number)
  default     = {}
}

locals {
  domains = toset(keys(var.protonmail))

  # Same records as addProtonmailRecords in dnsimple/dnsimple.go. Pulumi set a
  # TTL only on the verification TXT and the first MX; the others use the
  # DNSimple default, 3600.
  protonmail_records = merge([
    for domain, pm in var.protonmail : {
      "${domain} protonmail-verification" = { zone = domain, name = "", type = "TXT", value = pm.verification, ttl = 300, priority = null }
      "${domain} mx-mail"                 = { zone = domain, name = "", type = "MX", value = "mail.protonmail.ch", ttl = 300, priority = 10 }
      "${domain} mx-mailsec"              = { zone = domain, name = "", type = "MX", value = "mailsec.protonmail.ch", ttl = 3600, priority = 20 }
      "${domain} spf"                     = { zone = domain, name = "", type = "TXT", value = "\"v=spf1 include:_spf.protonmail.ch ~all\"", ttl = 3600, priority = null }
      "${domain} dkim1"                   = { zone = domain, name = "protonmail._domainkey", type = "CNAME", value = "protonmail.domainkey.${pm.dkim}.domains.proton.ch", ttl = 3600, priority = null }
      "${domain} dkim2"                   = { zone = domain, name = "protonmail2._domainkey", type = "CNAME", value = "protonmail2.domainkey.${pm.dkim}.domains.proton.ch", ttl = 3600, priority = null }
      "${domain} dkim3"                   = { zone = domain, name = "protonmail3._domainkey", type = "CNAME", value = "protonmail3.domainkey.${pm.dkim}.domains.proton.ch", ttl = 3600, priority = null }
      "${domain} dmarc"                   = { zone = domain, name = "_dmarc", type = "TXT", value = pm.dmarc, ttl = 3600, priority = null }
    }
  ]...)

  all_records = merge(local.protonmail_records, var.records)
}

resource "dnsimple_domain" "this" {
  for_each = local.domains
  name     = each.key

  # Like pulumi.Protect(true): deleting the domain would lose the mail.
  lifecycle {
    prevent_destroy = true
  }
}

import {
  for_each = local.domains
  to       = dnsimple_domain.this[each.key]
  id       = each.key
}

resource "dnsimple_zone_record" "this" {
  for_each  = local.all_records
  zone_name = each.value.zone
  name      = each.value.name
  type      = each.value.type
  value     = each.value.value
  ttl       = each.value.ttl
  priority  = each.value.priority

  depends_on = [dnsimple_domain.this]
}

import {
  for_each = var.import_record_ids
  to       = dnsimple_zone_record.this[each.key]
  id       = "${local.all_records[each.key].zone}_${each.value}"
}

output "record_ids" {
  description = "DNSimple record ID per record key."
  value       = { for k, r in dnsimple_zone_record.this : k => r.id }
}
