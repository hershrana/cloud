#
#   Deploy config for hershrana/jira - a Spring Boot backend on the app box and
#   an Angular bundle served by nginx. Ported from the repo's own
#   .github/workflows/deploy.yml so a local run and a CI run do the same thing.
#
#   Run with:  .\Deploy-App.ps1 jira -Tenant purvi
#
#   This file says WHAT to build and WHERE it goes on the box. It says nothing
#   about which machine that is: targets name a role, and the tenant config
#   (scripts\deploy\tenants\<name>.psd1) resolves the role to an address, key
#   and service account. That split is what lets this deploy to any tenant.
#
@{
    Name          = 'jira'

    # Used when -Tenant is omitted. Remove it to force the tenant to be named
    # explicitly on every run.
    DefaultTenant = 'purvi'

    RepoPath      = 'env:JIRA_REPO'

    # Build steps run in order, each from its own working directory (relative to
    # RepoPath). These are the Windows equivalents of the workflow's commands:
    # mvnw.cmd rather than ./mvnw, since the shell wrapper needs bash.
    Build         = @(
        @{
            Name    = 'backend'
            Command = '.\mvnw.cmd -B "-Dmaven.test.skip=true" clean package'
        },
        @{
            Name             = 'frontend'
            WorkingDirectory = 'frontend'
            Command          = @(
                'npm ci',
                'npx ng build --configuration production --base-href /jira/'
            )
        }
    )

    # Each target uploads one file to Staging, then runs Remote over ssh.
    # Remote entries are joined with && , so the first failure stops the rest.
    # {{...}} tokens come from the selected tenant's Vars.
    Deploy        = @(
        @{
            Name    = 'backend'
            Role    = 'app'
            Source  = 'target\jira-*.jar'
            Staging = '/tmp/jira.jar'
            Remote  = @(
                'sudo mv /tmp/jira.jar /opt/jira/jira.jar',
                'sudo chown {{AppUser}}:{{AppGroup}} /opt/jira/jira.jar',
                'sudo restorecon /opt/jira/jira.jar',
                'sudo systemctl restart jira-backend'
            )
        },
        @{
            Name      = 'frontend'
            Role      = 'nginx'
            # SourceDir is tarred and unpacked on the far side. Angular 17+ adds
            # the browser/ level; drop it if this build targets an older layout.
            SourceDir = 'frontend\dist\jira-frontend\browser'
            Staging   = '/tmp/jira-frontend.tgz'
            Remote    = @(
                'sudo rm -rf {{WebRoot}}/jira/*',
                'sudo tar -C {{WebRoot}}/jira -xzf /tmp/jira-frontend.tgz',
                'sudo systemctl reload nginx'
            )
        }
    )
}
