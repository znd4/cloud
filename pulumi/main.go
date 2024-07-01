// This is where we'll use pulumi to configure pulumi
package main

import (
	"os"

	"github.com/pulumi/pulumi-pulumiservice/sdk/go/pulumiservice"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func withStack(stack string) func(args *pulumiservice.DeploymentSettingsArgs) {
	return func(args *pulumiservice.DeploymentSettingsArgs) {
		args.Stack = pulumi.String(stack)
	}
}

func withGitSourceContext(
	gitSourceArgs pulumiservice.DeploymentSettingsGitSourceArgs,
) func(args *pulumiservice.DeploymentSettingsArgs) {
	return func(args *pulumiservice.DeploymentSettingsArgs) {
		args.SourceContext = pulumiservice.DeploymentSettingsSourceContextArgs{
			Git: gitSourceArgs,
		}
	}
}

func withBranch(branch string) func(gsa *pulumiservice.DeploymentSettingsGitSourceArgs) {
	return func(gsa *pulumiservice.DeploymentSettingsGitSourceArgs) {
		gsa.Branch = pulumi.String(branch)
	}
}

func withRepoDir(repoDir string) func(gsa *pulumiservice.DeploymentSettingsGitSourceArgs) {
	return func(gsa *pulumiservice.DeploymentSettingsGitSourceArgs) {
		gsa.RepoDir = pulumi.String(repoDir)
	}
}

func newGitSourceArgs(opts ...func(gsa *pulumiservice.DeploymentSettingsGitSourceArgs)) pulumiservice.DeploymentSettingsGitSourceArgs {
	result := pulumiservice.DeploymentSettingsGitSourceArgs{}
	for _, opt := range opts {
		opt(&result)
	}
	return result
}

func withGithubConfig(githubConfig pulumiservice.DeploymentSettingsGithubArgs) func(*pulumiservice.DeploymentSettingsArgs) {
	return func(dsa *pulumiservice.DeploymentSettingsArgs) {
		dsa.Github = githubConfig
	}
}

func newDeploymentSettings(
	ctx *pulumi.Context,
	name string,
	opts ...func(args *pulumiservice.DeploymentSettingsArgs),
) error {
	args := &pulumiservice.DeploymentSettingsArgs{
		Project:      pulumi.String(os.Getenv(pulumi.EnvProject)),
		Organization: pulumi.String(os.Getenv(pulumi.EnvOrganization)),
	}
	for _, opt := range opts {
		opt(args)
	}
	_, err := pulumiservice.NewDeploymentSettings(
		ctx,
		name,
		args,
	)
	return err
}

func newGithubConfig(paths []string) pulumiservice.DeploymentSettingsGithubArgs {
	return pulumiservice.DeploymentSettingsGithubArgs{
		Repository:          pulumi.String("znd4/cloud"),
		DeployCommits:       pulumi.BoolPtr(true),
		PreviewPullRequests: pulumi.BoolPtr(true),
		Paths:               pulumi.ToStringArray(paths),
	}
}

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		var err error
		err = newDeploymentSettings(
			ctx,
			"dnsimple",
			withStack("dns"),
			withGitSourceContext(newGitSourceArgs(withBranch("main"), withRepoDir("dnsimple"))),
			withGithubConfig(newGithubConfig([]string{"dnsimple"})),
		)
		if err != nil {
			return err
		}
		err = newDeploymentSettings(
			ctx,
			"pulumi",
			withStack("pulumi"),
			withGitSourceContext(newGitSourceArgs(withBranch("main"), withRepoDir("pulumi"))),
			withGithubConfig(newGithubConfig([]string{"pulumi"})),
		)
		if err != nil {
			return err
		}

		return nil
	})
}
