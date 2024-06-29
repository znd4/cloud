package main

import (
	"fmt"

	"github.com/pulumi/pulumi-dnsimple/sdk/v3/go/dnsimple"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func domain(ctx *pulumi.Context, domain string) (*dnsimple.Domain, error) {
	return dnsimple.NewDomain(ctx, domain, &dnsimple.DomainArgs{
		Name: pulumi.String(domain),
	}, pulumi.Protect(true))
}

type ProtonmailRecordInputs struct {
	verificationString pulumi.String
	dkim               pulumi.String
	dmarc              pulumi.String
}

var protonmailInputMap = map[string]ProtonmailRecordInputs{
	"znd4.dev": {
		verificationString: "protonmail-verification=f425a51143cba67038b420d2012840c02db726c3",
		dkim:               "dgwsf7fj6my2r3gc3nmtvkfmamr5klvflmeb4kdfe6ojl2asgwula",
		dmarc:              "v=DMARC1; p=quarantine",
	},
	"znd4.me": {
		verificationString: "protonmail-verification=bf0b2c0048c78ef0584a1a8fc2cd3cf13828fd3a",
		dkim:               "dspg66b3xa4h6ddxwhskf5bbduujpap6l6f7dktkxrrs624p7k34a",
		dmarc:              "v=DMARC1; p=quarantine",
	},
}

func addProtonmailRecords(ctx *pulumi.Context, domainName string) error {
	var err error
	inputs := protonmailInputMap[domainName]
	_, err = dnsimple.NewZoneRecord(ctx, fmt.Sprintf("zane@%s TXT", domainName), &dnsimple.ZoneRecordArgs{
		Name:     pulumi.String(""),
		ZoneName: pulumi.String(domainName),
		Type:     pulumi.String("TXT"),
		Value:    inputs.verificationString,
		Ttl:      pulumi.String("300"),
	})
	if err != nil {
		return err
	}
	_, err = dnsimple.NewZoneRecord(ctx, fmt.Sprintf("zane@%s mail MX", domainName), &dnsimple.ZoneRecordArgs{
		Name:     pulumi.String(""),
		ZoneName: pulumi.String(domainName),
		Type:     pulumi.String("MX"),
		Value:    pulumi.String("mail.protonmail.ch"),
		Priority: pulumi.String("10"),
		Ttl:      pulumi.String("300"),
	})
	if err != nil {
		return err
	}
	_, err = dnsimple.NewZoneRecord(ctx, fmt.Sprintf("zane@%s mailsec MX", domainName), &dnsimple.ZoneRecordArgs{
		Name:     pulumi.String(""),
		ZoneName: pulumi.String(domainName),
		Type:     pulumi.String("MX"),
		Value:    pulumi.String("mailsec.protonmail.ch"),
		Priority: pulumi.String("20"),
	})
	if err != nil {
		return err
	}
	_, err = dnsimple.NewZoneRecord(ctx, fmt.Sprintf("zane@%s SPF", domainName), &dnsimple.ZoneRecordArgs{
		Name:     pulumi.String(""),
		ZoneName: pulumi.String(domainName),
		Type:     pulumi.String("TXT"),
		Value:    pulumi.String("v=spf1 include:_spf.protonmail.ch ~all"),
	})
	if err != nil {
		return err
	}
	for _, i := range []string{"", "2", "3"} {
		name := pulumi.String(fmt.Sprintf("protonmail%s._domainkey", i))
		_, err = dnsimple.NewZoneRecord(ctx, fmt.Sprintf("zane@%s DKIM - %s", domainName, name), &dnsimple.ZoneRecordArgs{
			Name:     name,
			ZoneName: pulumi.String(domainName),
			Type:     pulumi.String("CNAME"),
			Value: pulumi.String(fmt.Sprintf(
				"protonmail%s.domainkey.%s.domains.proton.ch.",
				i,
				inputs.dkim,
			)),
		})
		if err != nil {
			return err
		}
	}
	_, err = dnsimple.NewZoneRecord(ctx, fmt.Sprintf("zane@%s DMARC", domainName), &dnsimple.ZoneRecordArgs{
		Name:     pulumi.String("_dmarc"),
		ZoneName: pulumi.String(domainName),
		Type:     pulumi.String("TXT"),
		Value:    inputs.dmarc,
	})
	if err != nil {
		return err
	}
	return nil
}
