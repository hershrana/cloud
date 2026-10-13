#
#   OCI tenant: revakunj
#
#   See purvi.psd1 for what each field means.
#
#   These are the boxes of the terraform workspace 'purvi'. Roles:
#     app   - kids (5900) and learning (5902)
#     nginx - the three SPAs, plus solar (5901), which runs here and not on 'app'
#
#   Unlike purvi/jira, the deploy user writes into /opt/revakunj/<app> and
#   /var/www/<app> without sudo (it owns both); its only sudo right is
#   "systemctl restart revakunj-<app>". See scripts/deploy/revakunj.psd1.
#
@{
    Name   = 'revakunj'

    SshKey = 'env:REVAKUNJ_SSH_KEY'
    User   = 'opc'

    Hosts  = @{
        app   = 'env:REVAKUNJ_APP_HOST'
        nginx = 'env:REVAKUNJ_NGINX_HOST'
    }

    Vars   = @{
        # rp-app is the unprivileged account the systemd units run as. The jars
        # are owned by opc and readable by rp-app via the setgid app dir, so a
        # deploy never chowns anything.
        AppUser  = 'rp-app'
        AppGroup = 'rp-app'
        AppRoot  = '/opt/revakunj'
        WebRoot  = '/var/www'
    }
}
