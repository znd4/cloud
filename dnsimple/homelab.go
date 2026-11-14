package main

import (
	"fmt"

	"github.com/pulumi/pulumi-dnsimple/sdk/v3/go/dnsimple"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// addHomelabAcmeRecords delegates acme.znd4.dev to deSEC and points the
// homelab ACME challenge name at it. The homelab Caddy then writes DNS-01 TXT
// records in deSEC with a token that cannot change this zone (MX, SPF, DKIM).
// See https://github.com/znd4/homelab/blob/main/docs/decisions/0003-names-and-tls.md
func addHomelabAcmeRecords(ctx *pulumi.Context) error {
	const zone = "znd4.dev"
	for _, ns := range []string{"ns1.desec.io", "ns2.desec.org"} {
		_, err := dnsimple.NewZoneRecord(ctx, fmt.Sprintf("%s acme NS %s", zone, ns), &dnsimple.ZoneRecordArgs{
			ZoneName: pulumi.String(zone),
			Name:     pulumi.String("acme"),
			Type:     pulumi.String("NS"),
			Value:    pulumi.String(ns),
		})
		if err != nil {
			return err
		}
	}
	_, err := dnsimple.NewZoneRecord(ctx, fmt.Sprintf("%s _acme-challenge.home CNAME", zone), &dnsimple.ZoneRecordArgs{
		ZoneName: pulumi.String(zone),
		Name:     pulumi.String("_acme-challenge.home"),
		Type:     pulumi.String("CNAME"),
		Value:    pulumi.String("_acme-challenge.acme.znd4.dev"),
	})
	return err
}
