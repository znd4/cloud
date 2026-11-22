# infra

OpenTofu and Terragrunt for DNS. The layout is the same as in
`znd4/homelab/infra`.

```
infra/
  root.hcl                        state backend, state encryption, CLI config
  tofu.tfrc                       OpenTofu CLI config: the oci_mirror for znd4/* providers
  secrets.env                     1Password references (not values)
  catalog/
    modules/dnsimple/             DNSimple domains and records (replaces dnsimple/ in Pulumi)
    modules/desec/                deSEC zone acme.znd4.dev and the hl01-acme token
    units/<unit>/terragrunt.hcl   inputs for a module
    units/<unit>/.terraform.lock.hcl
  live/prod/terragrunt.stack.hcl  the stack: desec, dnsimple
```

There is one environment, `prod`. The Pulumi stacks use the same name
(`prod/pulumi`), and the homelab uses its one real environment (`home`) in
the same way.

## Tools

Use the dev shell: `nix develop`. It has OpenTofu, Terragrunt, the 1Password
CLI and `gh`.

You need OpenTofu 1.10 or later for the `oci_mirror`. You need 1.13 or later
for `tofu providers lock -oci-mirror`.

## Credentials

The providers read these variables:

| Variable | 1Password reference |
| --- | --- |
| `DNSIMPLE_TOKEN` | `op://Pulumi/DNSimple Token/credential` |
| `DNSIMPLE_ACCOUNT` | `op://Pulumi/DNSimple Token/account_id` |
| `DESEC_TOKEN` | `op://Cloud CI/desec/credential` |
| `TF_VAR_state_passphrase` | `op://Cloud CI/tofu-state-passphrase/credential` |

`secrets.env` has these references. Run each command through 1Password:

```sh
op run --env-file=infra/secrets.env -- terragrunt stack run plan --working-dir infra/live/prod
```

`op run` resolves each reference the same way as `op read`, and it masks the
values in the output.

The deSEC token needs `perm_manage_tokens` and `perm_create_domain`.

The state passphrase item does not exist yet. Make it one time:

```sh
openssl rand -base64 32 | nix run .#put-secret -- tofu-state-passphrase
```

If you lose the passphrase, you cannot read the state.

## Provider installation

The deSEC provider (`znd4/desec`) is not in a registry. It is an OCI artifact
at `ghcr.io/znd4/opentofu-provider-desec`. `tofu.tfrc` tells OpenTofu to get
`registry.opentofu.org/znd4/*` from there, and all other providers from their
registry.

`root.hcl` sets `TF_CLI_CONFIG_FILE` to `infra/tofu.tfrc` for each tofu
command that Terragrunt runs. You do not set it yourself, and CI does not
set it.

If you run `tofu` without Terragrunt, set it yourself:

```sh
export TF_CLI_CONFIG_FILE="$PWD/infra/tofu.tfrc"
```

## Lock files

Each unit has a committed `.terraform.lock.hcl` in `catalog/units/<unit>/`.
Terragrunt copies it into the generated unit, and copies it back after
`init`.

- `dnsimple`: the OpenTofu registry returns hashes for all platforms. A
  normal `init` is enough.
- `desec`: an OCI mirror has no signed checksum list. `init` adds the hash for
  your platform only. CI runs on `linux_amd64`, so add the other platforms:

  ```sh
  cd infra/catalog/modules/desec
  tofu providers lock \
    -oci-mirror='ghcr.io/znd4/opentofu-provider-{type}' \
    -platform=linux_amd64 -platform=linux_arm64 \
    -platform=darwin_arm64 -platform=darwin_amd64
  mv .terraform.lock.hcl ../../units/desec/.terraform.lock.hcl
  ```

  The `-oci-mirror` value is an RFC 6570 template: `{type}`, not `${type}`.
  OpenTofu before 1.13 does not have this option (opentofu#3620).

## State backend

`CLOUD_TOFU_BACKEND` selects the backend:

| Value | Backend |
| --- | --- |
| `local` (default) | `infra/.state/<unit>/tofu.tfstate`. Git ignores it. |
| `s3` | A Cloudflare R2 bucket. Fill the `TODO(tofu-backend)` values in `root.hcl` first. |

Both backends encrypt state and plans with `TF_VAR_state_passphrase`. The
state holds the `hl01-acme` token secret.

To move from `local` to `s3`, run `init -migrate-state` in each unit with
`CLOUD_TOFU_BACKEND=s3`. Use the same passphrase.

## First run: take over DNS from Pulumi

The `dnsimple` unit imports the two domains and the 16 Proton Mail records
that Pulumi made. It adds three new records for the homelab (from #5): two NS
records for `acme`, and the CNAME `_acme-challenge.home`.

1. Generate the stack:

   ```sh
   terragrunt stack generate --working-dir infra/live/prod
   ```

2. Make a plan:

   ```sh
   op run --env-file=infra/secrets.env -- terragrunt stack run plan --working-dir infra/live/prod
   ```

3. Read the plan of the `dnsimple` unit. It must say:

   ```
   Plan: 18 to import, 3 to add, 0 to change, 0 to destroy.
   ```

   WARNING: Do not apply if an imported record shows a change, or if a
   record will be destroyed. Proton Mail stops if the MX, SPF or DKIM records
   change.

4. Read the plan of the `desec` unit. It must add 4 resources: the domain,
   the token and two policies.
5. Apply:

   ```sh
   op run --env-file=infra/secrets.env -- terragrunt stack run apply --working-dir infra/live/prod
   ```

   Terragrunt applies `desec` first. So the zone exists before the NS records
   point at it.

6. Make sure that the delegation works:

   ```sh
   dig +short NS acme.znd4.dev
   ```

   The output must show `ns1.desec.io.` and `ns2.desec.org.`.

7. Save the token for the homelab. The value goes through a pipe and is
   never printed:

   ```sh
   op run --env-file=infra/secrets.env -- \
     terragrunt output -raw token --working-dir infra/live/prod/.terragrunt-stack/desec \
     | SECRET_VAULT=Homelab nix run .#put-secret -- hl01-acme
   ```

8. Close #5. This stack replaces it.

## Retire the Pulumi program

Do this after the apply in the previous section. Then Pulumi forgets the
records, and OpenTofu manages them.

WARNING: Never run `pulumi destroy` on `dns/dns`. It deletes the real
domains and records, and Proton Mail stops.

1. Make sure that OpenTofu manages everything:

   ```sh
   op run --env-file=infra/secrets.env -- terragrunt stack run plan --working-dir infra/live/prod
   ```

   Both units must show `No changes.`

2. Go to the Pulumi program and select the stack:

   ```sh
   cd dnsimple
   pulumi stack select znd4/dns/dns
   ```

3. Remove the protection from the two domains:

   ```sh
   pulumi state unprotect --all --yes
   ```

4. List the resources:

   ```sh
   pulumi stack --show-urns
   ```

5. Remove each `dnsimple:index/zoneRecord:ZoneRecord` and
   `dnsimple:index/domain:Domain` resource from the state. This changes only
   the Pulumi state, not DNSimple:

   ```sh
   pulumi stack export \
     | jq -r '.deployment.resources[] | select(.type | startswith("dnsimple:index/")) | .urn' \
     | while read -r urn; do pulumi state delete --yes "$urn"; done
   ```

6. Make sure that only the stack and the provider are left:

   ```sh
   pulumi stack --show-urns
   ```

7. Remove the empty stack. `pulumi stack rm` refuses a stack that still has
   resources:

   ```sh
   pulumi stack rm znd4/dns/dns
   ```

   If it refuses because of the default provider, run
   `pulumi state delete --yes <provider urn>` first. Do not add `--force`.

8. In a new pull request, delete `dnsimple/` and its entry in
   `.github/workflows/pulumi-preview.yaml`.

## Checks without credentials

These commands need no DNSimple or deSEC access:

```sh
terragrunt stack generate --working-dir infra/live/prod
TF_VAR_state_passphrase=dummy-passphrase terragrunt run --all --working-dir infra/live/prod -- validate
```
