package main

import (
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		var err error
		err = addPulumi(ctx)
		if err != nil {
			return err
		}

		return nil
	})
}
