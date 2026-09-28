#
#   OCI tenant: purvi
#
#   Owns the boxes, the SSH key and the service accounts. App configs refer to
#   boxes by role ('app', 'nginx'), never by address, so the same app config
#   deploys to any tenant that defines the roles it needs.
#
#   Values written as "env:NAME" are read from the environment at run time,
#   because this repo (hershrana/cloud) is public.
#
@{
    Name   = 'purvi'

    SshKey = 'env:PURVI_SSH_KEY'
    User   = 'opc'

    # Box roles. Add a role here and any app config may target it.
    Hosts  = @{
        app   = 'env:PURVI_APP_HOST'
        nginx = 'env:PURVI_NGINX_HOST'
    }

    # Substituted into a target's Staging and Remote strings as {{name}}.
    # Service accounts differ between tenants, so app configs should not name
    # them directly.
    Vars   = @{
        AppUser  = 'rp-app'
        AppGroup = 'rp-app'
        WebRoot  = '/var/www'
    }
}
