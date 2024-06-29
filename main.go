package main

import (
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		var err error
		for _, domainName := range []string{"znd4.dev", "znd4.me"} {
			_, err = domain(ctx, domainName)
			if err != nil {
				return err
			}
			err = addProtonmailRecords(ctx, domainName)
			if err != nil {
				return err
			}
		}
		err = addPulumi(ctx)

		return err
	})
}
