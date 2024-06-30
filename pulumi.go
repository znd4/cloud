// This is where we'll use pulumi to configure pulumi
package main

import (
	"os"

	"github.com/pulumi/pulumi-pulumiservice/sdk/go/pulumiservice"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func githubConfig(paths []string) pulumiservice.DeploymentSettingsGithubPtrInput {
	return pulumiservice.DeploymentSettingsGithubPtr(
		&pulumiservice.DeploymentSettingsGithubArgs{
			Repository:          pulumi.String("znd4/cloud"),
			DeployCommits:       pulumi.BoolPtr(true),
			PreviewPullRequests: pulumi.BoolPtr(true),
			Paths:               pulumi.ToStringArray(paths),
		},
	)
}

func addPulumi(ctx *pulumi.Context) error {
	var err error
	_, err = pulumiservice.NewDeploymentSettings(
		ctx,
		"dnsimple",
		&pulumiservice.DeploymentSettingsArgs{
			Stack:        pulumi.String("dnsimple"),
			Project:      pulumi.String(os.Getenv(pulumi.EnvProject)),
			Organization: pulumi.String(os.Getenv(pulumi.EnvOrganization)),
			SourceContext: pulumiservice.DeploymentSettingsSourceContextArgs{
				Git: pulumiservice.DeploymentSettingsGitSourceArgs{
					Branch:  pulumi.String("main"),
					RepoDir: pulumi.String("dnsimple"),
				},
			},
			Github: githubConfig([]string{"dnsimple"}),
		},
	)
	if err != nil {
		return err
	}
	_, err = pulumiservice.NewDeploymentSettings(
		ctx,
		"znd4/cloud access",
		&pulumiservice.DeploymentSettingsArgs{
			Stack:        pulumi.String(os.Getenv(pulumi.EnvStack)),
			Project:      pulumi.String(os.Getenv(pulumi.EnvProject)),
			Organization: pulumi.String(os.Getenv(pulumi.EnvOrganization)),
			SourceContext: pulumiservice.DeploymentSettingsSourceContextArgs{
				Git: pulumiservice.DeploymentSettingsGitSourceArgs{
					Branch:  pulumi.StringPtr("main"),
					RepoDir: pulumi.StringPtr("."),
				},
			},
			Github: githubConfig([]string{"*"}),
		})
	if err != nil {
		return err
	}
	return nil
}
