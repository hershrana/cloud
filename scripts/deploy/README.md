# Local deploys

`..\Deploy-App.ps1` builds an app on this machine and ships it to an OCI tenant
over SSH — the same steps a GitHub Actions deploy workflow runs, minus the
runner minutes and the artifact storage quota.

```powershell
.\Deploy-App.ps1 jira -Tenant purvi             # build, then deploy every target
.\Deploy-App.ps1 jira -Tenant purvi -DryRun     # print every command, run none
.\Deploy-App.ps1 jira -Tenant purvi -SkipBuild  # reuse the last build output
.\Deploy-App.ps1 jira -Tenant purvi -Target backend
.\Deploy-App.ps1 -ListTenants
```

## Two kinds of config

The split is what makes one app deployable to several tenants:

| File | Answers | Holds |
|---|---|---|
| `<app>.psd1` | *what to build, and where it goes on the box* | build commands, source globs, remote paths, roles |
| `tenants\<tenant>.psd1` | *which machines, whose key* | host addresses per role, SSH key, service accounts |

An app target names a box by **role** (`app`, `nginx`) — never by address. The
tenant resolves that role. So `jira -Tenant purvi` and `jira -Tenant revakunj`
run identical build and remote steps against different machines with different
keys.

Adding an app means adding one `.psd1`. Adding a tenant means adding one
`tenants\*.psd1`. Neither means editing the script.

### Which tenant gets used

In order, first one wins:

1. `-Tenant <name>`
2. `DefaultTenant` in the app config
3. `$env:OCI_TENANT`

The env var is last deliberately: setting it for convenience can never silently
redirect a deploy that named its tenant explicitly.

## Secrets stay out of this repo

`hershrana/cloud` is public, so no config here holds a box address, a key path
or a checkout path. Any config value written as `env:NAME` is read from
`$env:NAME` at run time, and the script fails with a clear message if it is
unset.

```powershell
setx OCI_TENANT      "purvi"
setx JIRA_REPO       "D:\cloud\jira"
setx PURVI_SSH_KEY   "$HOME\.ssh\oci_purvi"
setx PURVI_APP_HOST  "<app box IP>"
setx PURVI_NGINX_HOST "<nginx box IP>"

setx REVAKUNJ_REPO       "D:\cloud\revakunj"
setx REVAKUNJ_SSH_KEY    "$HOME\.ssh\oci_purvi"
setx REVAKUNJ_APP_HOST   "<app box IP>"
setx REVAKUNJ_NGINX_HOST "<nginx box IP>"
```

`setx` affects new shells only — reopen the terminal afterwards.

## Tenant config shape

```powershell
@{
    Name   = 'purvi'
    SshKey = 'env:PURVI_SSH_KEY'
    User   = 'opc'                  # default SSH user for this tenant

    Hosts  = @{                     # roles an app config may target
        app   = 'env:PURVI_APP_HOST'
        nginx = 'env:PURVI_NGINX_HOST'
    }

    Vars   = @{                     # substituted as {{name}} in Staging/Remote
        AppUser  = 'rp-app'
        AppGroup = 'rp-app'
        WebRoot  = '/var/www'
    }
}
```

`Vars` exists so an app config never hard-codes a service account or a web root
that differs between tenants.

## App config shape

```powershell
@{
    Name          = 'myapp'
    DefaultTenant = 'purvi'         # optional
    RepoPath      = 'env:MYAPP_REPO'

    Build = @(
        @{ Name = 'backend';  Command = '.\mvnw.cmd -B clean package' },
        @{ Name = 'frontend'; WorkingDirectory = 'frontend'
           Command = @('npm ci', 'npx ng build --configuration production') }
    )

    Deploy = @(
        # A file target: Source is a glob, newest match wins.
        @{ Name = 'backend'; Role = 'app'
           Source = 'target\myapp-*.jar'; Staging = '/tmp/myapp.jar'
           Remote = @('sudo mv /tmp/myapp.jar /opt/myapp/myapp.jar',
                      'sudo chown {{AppUser}}:{{AppGroup}} /opt/myapp/myapp.jar',
                      'sudo systemctl restart myapp') },

        # A directory target: tarred locally, unpacked on the far side.
        @{ Name = 'frontend'; Role = 'nginx'
           SourceDir = 'frontend\dist\myapp\browser'; Staging = '/tmp/myapp.tgz'
           Remote = @('sudo rm -rf {{WebRoot}}/myapp/*',
                      'sudo tar -C {{WebRoot}}/myapp -xzf /tmp/myapp.tgz',
                      'sudo systemctl reload nginx') }
    )
}
```

Notes:

- `Remote` entries are joined with `&&`, so the first failure stops the rest.
- A target may use `HostName` instead of `Role` for a one-off box no tenant
  lists; `env:NAME` works there too.
- Uploads land in `/tmp` and are moved into place by `Remote`, because the SSH
  user cannot write to `/opt` or `/var/www` and `scp` cannot run under `sudo`.
- Use `mvnw.cmd`, not `./mvnw` — the extensionless wrapper needs bash.
- On SELinux boxes, add `sudo restorecon <path>` to `Remote` after moving a
  file into `/opt`, or systemd will refuse to execute it.
- Host keys use `StrictHostKeyChecking=accept-new`: trusted on first contact,
  pinned after, and never an interactive prompt mid-deploy.
- Roles and `{{vars}}` are resolved before anything is uploaded, so a config
  mistake fails while the box is still untouched.

## Per-app notes

### revakunj

The two tenants do not share a sudo policy, and an app config has to match the
one on its boxes:

| | purvi / jira | revakunj |
|---|---|---|
| deploy user owns the app dir | no | yes (`/opt/revakunj/<app>`, `/var/www/<app>`) |
| upload lands in | `/tmp`, then `sudo mv` | the final directory, then plain `mv` |
| sudo rights of the deploy user | broad | `systemctl restart revakunj-<app>` only |

So `revakunj.psd1` uses no `sudo` except the restart. Copying jira's `sudo mv` /
`sudo chown` / `sudo restorecon` lines into it would make every deploy hang on a
password prompt.

Two more things it deliberately does not do:

- **It never writes `/opt/revakunj/<app>/env`.** That file holds the DB
  password, the JWT secret and `APP_WEBAUTHN_RP_ID`; only the GitHub deploy job
  writes it, from repo secrets. A local deploy reuses what is on the box, so a
  new setting has to be added through CI or by hand.
- **It does not run `npm ci` or rebuild the `@kids-finance/access` tarball.**
  Both frontends depend on `file:../../dist/access/kids-finance-access-1.0.0.tgz`,
  and CI rebuilds it every run because the lockfile pins a hash of a locally
  built artifact. Locally that is a one-time step after a dependency change:

  ```powershell
  cd D:\cloud\revakunj\frontend\access
  npm ci ; npm run build ; node post-build.js
  cd ..\..\dist\access ; npm pack --pack-destination .
  ```

The app box is a 1 GB `E2.1.Micro` running two JVMs (kids and learning). A full
run restarts both within a few seconds of each other, and two warming JVMs on
that box can reach the OOM killer — deploy them one at a time with `-Target`
when both changed.
