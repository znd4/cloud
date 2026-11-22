# The deSEC zone for ACME DNS-01 challenges, and the token that the homelab
# Caddy uses. See znd4/homelab docs/decisions/0003-names-and-tls.md.
#
# The token can write only the TXT RRset at _acme-challenge.<zone>. It cannot
# change znd4.dev (at DNSimple), which holds the Proton Mail records.
#
# The provider reads DESEC_TOKEN from the environment. That token needs
# perm_manage_tokens and perm_create_domain.

terraform {
  required_version = ">= 1.13.0"
  required_providers {
    desec = {
      # Not in a registry: infra/tofu.tfrc installs it from
      # ghcr.io/znd4/opentofu-provider-desec.
      source  = "znd4/desec"
      version = "~> 0.1"
    }
  }
}

provider "desec" {}

variable "zone" {
  description = "The deSEC zone, delegated from its parent with NS records."
  type        = string
}

variable "token_name" {
  description = "Name of the token for the ACME client."
  type        = string
}

variable "challenge_subname" {
  description = "The subname that the ACME client writes."
  type        = string
  default     = "_acme-challenge"
}

resource "desec_domain" "acme" {
  name = var.zone
}

resource "desec_token" "acme" {
  name = var.token_name
  # All permission flags stay false: the token cannot make domains or tokens.
}

# deSEC requires this policy before any other policy of the token. With
# perm_write = false (the default), it takes away all write access.
resource "desec_token_policy" "default" {
  token_id = desec_token.acme.id
}

resource "desec_token_policy" "challenge" {
  token_id   = desec_token.acme.id
  domain     = desec_domain.acme.name
  subname    = var.challenge_subname
  type       = "TXT"
  perm_write = true

  depends_on = [desec_token_policy.default]
}

output "zone" {
  value = desec_domain.acme.name
}

output "challenge_name" {
  description = "The name that the ACME client writes, for example _acme-challenge.acme.znd4.dev."
  value       = "${var.challenge_subname}.${desec_domain.acme.name}"
}

output "ds" {
  description = "DS records for a DNSSEC delegation from the parent zone."
  value       = desec_domain.acme.ds
}

output "token_id" {
  value = desec_token.acme.id
}

output "token" {
  description = "The token secret. Read it with: terragrunt output -raw token"
  value       = desec_token.acme.token
  sensitive   = true
}
