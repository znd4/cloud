// This is where we'll use pulumi to configure pulumi
package main

import (
	"github.com/pulumi/pulumi-pulumiservice/sdk/go/pulumiservice"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func addPulumi(ctx *pulumi.Context) error {
	_, err := pulumiservice.NewDeploymentSettings(
		ctx,
		"znd4/cloud access",
		&pulumiservice.DeploymentSettingsArgs{
			Stack:        pulumi.String("dev"),
			Project:      pulumi.String("cloud"),
			Organization: pulumi.String("znd4"),
			SourceContext: pulumiservice.DeploymentSettingsSourceContextArgs{
				Git: pulumiservice.DeploymentSettingsGitSourceArgs{
					Branch:  pulumi.StringPtr("/ref/heads/main"),
					RepoDir: pulumi.StringPtr("."),
				},
			},
			Github: pulumiservice.DeploymentSettingsGithubPtr(&pulumiservice.DeploymentSettingsGithubArgs{
				Repository:          pulumi.String("znd4/cloud"),
				DeployCommits:       pulumi.BoolPtr(true),
				PreviewPullRequests: pulumi.BoolPtr(true),
			}),
		})
	return err
}
