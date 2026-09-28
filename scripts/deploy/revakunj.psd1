#
#   Deploy config for hershrana/revakunj - three Spring Boot backends and three
#   Angular SPAs. Ported from the repo's own .github/workflows/deploy.yml (copy
#   in revakunj\github-workflow\deploy.yml) so a local run does what CI does.
#
#   Run with:  .\Deploy-App.ps1 revakunj -Tenant revakunj
#              .\Deploy-App.ps1 revakunj -Tenant revakunj -Target kids-backend
#
#   Differences from jira.psd1, both forced by how the boxes are set up
#   (revakunj\app-bootstrap-revakunj.sh):
#
#   1. NO sudo except systemctl restart. /etc/sudoers.d/revakunj grants opc
#      exactly "systemctl restart revakunj-<app>" and nothing else, so a
#      "sudo mv" or "sudo chown" here would hang on a password prompt. It does
#      not need them: opc owns /opt/revakunj/<app> (mode 2750, group rp-app)
#      and /var/www/<app> (opc:opc), so plain mv and tar are enough.
#   2. This does NOT write /opt/revakunj/<app>/env. That file holds the DB
#      password, the JWT secret and the WebAuthn rp-id, and only the GitHub
#      deploy job writes it (from repo secrets). A local deploy reuses whatever
#      env is already on the box. If a new setting is needed, add it there via
#      CI or by hand -- never put secrets in this repo.
#
#   Note on the Angular builds: node_modules and dist\access are expected to be
#   present already. CI runs "npm ci" and rebuilds the @kids-finance/access
#   tarball; locally that is a one-time step you do by hand after a dependency
#   change (see scripts\deploy\README.md).
#
@{
    Name          = 'revakunj'

    DefaultTenant = 'revakunj'

    RepoPath      = 'env:REVAKUNJ_REPO'

    Build         = @(
        @{
            Name    = 'backends'
            Command = 'mvn -B -q "-Dmaven.test.skip=true" -f backend\pom.xml clean package'
        },
        @{
            Name             = 'kids-frontend'
            WorkingDirectory = 'frontend\kids-money-frontend'
            # environment.ts ships with apiUrl '/api', which behind nginx is
            # jira's API, not this one. CI rewrites it the same way; the rewrite
            # is idempotent but it does dirty the revakunj working tree.
            Command          = @(
                '(Get-Content src\environments\environment.ts) -replace "apiUrl: .*", "apiUrl: ''/kids/api''" | Set-Content src\environments\environment.ts',
                'npx ng build --configuration production --base-href /kids/'
            )
        },
        @{
            Name             = 'solar-frontend'
            WorkingDirectory = 'frontend\solarelectricity-frontend'
            Command          = 'npx ng build --configuration production --base-href /solar/'
        },
        @{
            Name             = 'learning-frontend'
            WorkingDirectory = 'frontend\learning'
            Command          = 'npx ng build --configuration production --base-href /learning/'
        }
    )

    # Role 'app'   -> the box running kids (5900) and learning (5902)
    # Role 'nginx' -> the box serving the SPAs AND running solar (5901)
    Deploy        = @(
        @{
            Name    = 'kids-backend'
            Role    = 'app'
            Source  = 'backend\kids-money-game\target\kids-money-game-*.jar'
            # scp straight into the app dir: opc owns it, so no /tmp hop and no
            # sudo mv. The .new name plus mv keeps the swap atomic, so a failed
            # upload can never leave a half-written jar for systemd to start.
            Staging = '{{AppRoot}}/kids/app.jar.new'
            Remote  = @(
                'chmod 640 {{AppRoot}}/kids/app.jar.new',
                'mv {{AppRoot}}/kids/app.jar.new {{AppRoot}}/kids/app.jar',
                'sudo systemctl restart revakunj-kids'
            )
        },
        @{
            Name    = 'solar-backend'
            Role    = 'nginx'   # solar really does live on the nginx box
            Source  = 'backend\solar-ev-tracker\target\solar-ev-tracker-*.jar'
            Staging = '{{AppRoot}}/solar/app.jar.new'
            Remote  = @(
                'chmod 640 {{AppRoot}}/solar/app.jar.new',
                'mv {{AppRoot}}/solar/app.jar.new {{AppRoot}}/solar/app.jar',
                'sudo systemctl restart revakunj-solar'
            )
        },
        @{
            Name    = 'learning-backend'
            Role    = 'app'
            Source  = 'backend\learning\target\learning-*.jar'
            Staging = '{{AppRoot}}/learning/app.jar.new'
            Remote  = @(
                'chmod 640 {{AppRoot}}/learning/app.jar.new',
                'mv {{AppRoot}}/learning/app.jar.new {{AppRoot}}/learning/app.jar',
                'sudo systemctl restart revakunj-learning'
            )
        },

        # find -delete rather than "rm -rf dir/*": it clears dotfiles too and
        # leaves the directory itself, which is what carries the SELinux
        # httpd_sys_content_t label that nginx needs. Extracted files inherit it.
        @{
            Name      = 'kids-frontend'
            Role      = 'nginx'
            SourceDir = 'frontend\kids-money-frontend\dist\kids-money-frontend\browser'
            Staging   = '/tmp/revakunj-kids.tgz'
            Remote    = @(
                'find {{WebRoot}}/kids -mindepth 1 -delete',
                'tar -C {{WebRoot}}/kids -xzf /tmp/revakunj-kids.tgz',
                'rm -f /tmp/revakunj-kids.tgz'
            )
        },
        @{
            Name      = 'solar-frontend'
            Role      = 'nginx'
            SourceDir = 'frontend\solarelectricity-frontend\dist\solarelectricity-frontend\browser'
            Staging   = '/tmp/revakunj-solar.tgz'
            Remote    = @(
                'find {{WebRoot}}/solar -mindepth 1 -delete',
                'tar -C {{WebRoot}}/solar -xzf /tmp/revakunj-solar.tgz',
                'rm -f /tmp/revakunj-solar.tgz'
            )
        },
        @{
            Name      = 'learning-frontend'
            Role      = 'nginx'
            SourceDir = 'frontend\learning\dist\learning\browser'
            Staging   = '/tmp/revakunj-learning.tgz'
            Remote    = @(
                'find {{WebRoot}}/learning -mindepth 1 -delete',
                'tar -C {{WebRoot}}/learning -xzf /tmp/revakunj-learning.tgz',
                'rm -f /tmp/revakunj-learning.tgz'
            )
        }
    )
}
