# OCI Always-Free Deployment Runbook (feed this file to the AI agent)

> **How to use:** Open a new Copilot chat in this workspace and paste/attach this
> file with a message like *"Follow AI_DEPLOYMENT_RUNBOOK.md and deploy my apps."*
> The agent will ask for the few inputs below, then provision OCI infra, convert
> the apps to MySQL, deploy them, and wire up CI/CD — reproducing the working
> setup this file was distilled from.

---

## 0. What the agent must ask the user first

Collect these before doing anything. Everything else is derived/automated.

### 0.1 OCI credentials (for Terraform + OCI API)
| Input | Notes |
|-------|-------|
| `tenancy_ocid` | `ocid1.tenancy.oc1..…` |
| `user_ocid` | `ocid1.user.oc1..…` |
| `compartment_id` | Use `tenancy_ocid` to deploy in the root compartment |
| `region` | Must be your **home region** for Always Free (e.g. `ap-mumbai-1`) |
| `fingerprint` | API key fingerprint from the OCI console |
| `private_key_path` | Local path to the OCI API private key PEM (e.g. `C:/Users/<you>/.oci/oci_api_key.pem`) |
| `ssh_public_key` | Public key whose private half you hold (deploy/login key) |
| `mysql_admin_username` | e.g. `admin` |
| `mysql_admin_password` | Strong password; **never** route through the model — user types it into tfvars/terminal |

> **Never** ask for the MySQL password or any token via a picker/question tool —
> those go through the model. Have the user paste secrets directly into
> `terraform.tfvars` (gitignored) or the terminal.

### 0.2 Apps to deploy (repeatable block — ask once per app)
For **each** app collect:
| Field | Example (jira) | Example (todo) |
|-------|----------------|----------------|
| `name` | `jira` | `todo` |
| **Backend source** | GitHub URL *or* local folder | `C:\upi\jira` | `C:\upi\todo\todo` |
| **Frontend source** | GitHub URL *or* local folder (often a `frontend/` subdir) | `…\jira\frontend` | `…\todo\todo\frontend` |
| `backend_port` | `5857` | `5855` |
| `api_path_prefixes` | paths the frontend calls | `/api/jira`, `/api/auth` | `/api/tasks`, `/api/notes`, `/api/eod` |
| `db_name` | `jira` | `todo` |
| `base_href` | `/jira/` | `/todo/` |
| `db_style` | JPA/JDBC or R2DBC (reactive) | JPA | R2DBC |

- **Source = GitHub URL:** clone it. Private repos need auth (gh CLI or a PAT). If
  clone fails with *"Repository not found"* it's usually a private repo without
  credentials — ask the user to authenticate or provide a local checkout.
- **Source = local folder:** build straight from it. The deployed artifacts will
  include any uncommitted local edits — tell the user, and let them decide what
  to commit.

### 0.3 Domain name for a trusted SSL certificate (ask at startup — strongly recommended)
Browsers only trust HTTPS for a **domain name**, never for a bare IP. Without a
domain the site runs on a self-signed cert and every visitor sees **"Not secure"**.
Ask the user:

| Input | Notes |
|-------|-------|
| `domain` | e.g. `hbr.publicvm.com`. If they have none, **recommend a free one** — [DNSExit](https://dnsexit.com) gives free subdomains such as `<name>.publicvm.com` (also fine: DuckDNS, No-IP, FreeDNS). A paid domain works the same. |

What the user does (one time, in the DNS provider's console):
1. Create the host name and an **A record → the nginx box's public IP** (from
   `terraform output`). Reserve a static public IP in OCI first, or remember to
   update the A record whenever the box is recreated (DNSExit also has a dynamic-DNS
   update URL for that).
2. Wait until `nslookup <domain> 8.8.8.8` returns that IP. Only then issue the cert (§4 step 7).

No email or account with Let's Encrypt is needed. If the user declines, deploy with
the self-signed cert and tell them browsers will warn until a domain is added.

---

## 1. Target architecture (what we build)

```
Internet ──80──▶ [ Public VM  (~1 GB E2.1.Micro, public IP) ]
                     │  nginx (reverse proxy + static SPAs)
                     │    /<app>/            → /var/www/<app>   (Angular dist)
                     │    /api/<prefix>      → 127.0.0.1:<backend_port>
                     │  systemd: <app>-backend (Spring Boot jar, -Xmx192m)
                     └──3306──▶ MySQL HeatWave (private 10.0.2.x, no public IP)
```

- **One JVM per micro box.** Always Free gives 2× AMD micro (1 GB each) or ARM A1
  (capacity-permitting). A 1 GB box holds nginx + **one** Spring Boot backend; put
  a second backend on the other micro and proxy to its private IP. Both micros are
  only usable after the memory fixes in §3 (without them one may show ~498 MB).
  Talk to MySQL over the private VCN.
- **MySQL HeatWave** (`MySQL.Free`, 50 GB) is the only free managed DB — apps must
  use MySQL, not Postgres.

---

## 2. Non-negotiable Always-Free constraints (design around these)

1. **No NAT gateway** in free tier → don't create one; leave the private route
   table empty. Put the app/nginx box in a **public** subnet so it can `dnf`.
2. **No managed PostgreSQL** → convert every app to MySQL (see §6).
3. **A1 (ARM) is frequently `Out of host capacity`** in the home region →
   fall back to `VM.Standard.E2.1.Micro` (fixed shape, **no** `shape_config`).
4. **MySQL DB System quirks:** no `backup_policy` block, don't pin `mysql_version`
   (leave null), `is_highly_available = false`, `shape_name = "MySQL.Free"`.
   Creation takes **~21 minutes** — expect the long wait.
5. **Micro instances have 1 GB, but Oracle Linux can hide half of it.** The stock
   kernel cmdline has `crashkernel=1G-64G:448M,64G-:512M`; when it takes effect,
   kdump reserves 448 MB and `free -m` shows only **~498 MB**. Such a box
   OOM-thrashes as soon as `dnf` runs next to a JVM: SSH hangs at "banner
   exchange" and every API behind it returns **504**. It is not a smaller box;
   remove the reservation (§3) and it shows ~945 MB like the other one.
6. **Public IPs are ephemeral** — they change if an instance is recreated. Update
   GitHub secrets after any recreate, or reserve a static public IP.

---

## 3. Gotchas learned the hard way (apply these preemptively)

**Cloud-init / OS**
- In cloud-init: **create a 2 GB swapfile FIRST**, then install packages. Do **not**
  run `dnf update -y` on a 1 GB box (it OOM-wedges the instance). Only
  `dnf install -y <needed>`.
- **Reclaim the kdump memory and stop background `dnf`** on every micro, in
  cloud-init (as root) or once by hand (with `sudo`), then **reboot once**: the
  reservation is only released at boot.
  ```bash
  systemctl disable --now dnf-makecache.timer kdump
  ck=$(grep -o 'crashkernel=[^ ]*' /proc/cmdline) && grubby --update-kernel=ALL --remove-args="$ck"
  sed -i -E 's/ ?crashkernel=[^ "]*//' /etc/default/grub   # keep it off for future kernels
  sed -i -E 's/^auto_reset_crashkernel .*/auto_reset_crashkernel no/' /etc/kdump.conf
  ```
  `dnf-makecache.timer` refreshes repo metadata ~10 min after boot and then every
  hour or two, and each run needs ~350 MB. On a box left with ~498 MB next to a
  JVM, that run froze the whole instance until a console reboot. After the
  reboot, check `free -m` (≈ 945 total) and `cat /sys/kernel/kexec_crash_size` (`0`).
- **Never run full-repo `dnf` next to a running JVM**, and that includes Ansible's
  `dnf:` module. Install packages before starting backends, restricting repos:
  `dnf install -y --disablerepo='*' --enablerepo=ol9_baseos_latest,ol9_appstream <pkg>`.
- OL9 **firewalld blocks port 80** → `firewall-cmd --add-service=http --add-service=https`.
  Open backend ports only inside the VCN:
  `--add-rich-rule='rule family=ipv4 source address=10.0.0.0/16 port port=5855-5857 protocol=tcp accept'`.
- OL9 **SELinux is Enforcing**:
  - Static files under `/var/www` give **403** unless labeled:
    `chcon -R -t httpd_sys_content_t /var/www`.
  - nginx→backend proxy is blocked unless: `setsebool -P httpd_can_network_connect 1`.

**nginx**
- Use path-prefix `location /api/<x>` **WITHOUT a trailing slash**, and
  `proxy_pass http://127.0.0.1:<port>;` **without a URI** (preserve the full path).
  A trailing-slash location (`location /api/x/`) makes nginx **301-redirect**
  bare-path calls → then Spring Boot 4 (trailing-slash matching disabled) returns
  **404**. This bit us; don't repeat it.
- **One owner per nginx file.** `ansible/playbooks/nginx.yml` and
  `terraform/deploy/nginx-bootstrap.sh` both write `/etc/nginx/conf.d/rp-app.conf`.
  Running the playbook on a box set up by a bootstrap script replaced the app
  routes with `location / → <app-ip>:8080` (nothing listens there), so every path
  outside the SPA prefixes **504'd after 10 s**. Configure each box with one tool
  only, and never run `site.yml` on it (§5).
- **TLS: use a domain + Let's Encrypt via `acme.sh`, not certbot.** certbot needs
  EPEL + a `dnf` install (the memory spike §3 warns about); `acme.sh` is a single
  shell script. `terraform/deploy/enable-letsencrypt.sh` installs it, issues an
  ECDSA cert with the HTTP-01 webroot `/var/www/acme`, writes
  `/etc/nginx/ssl/<domain>.{crt,key}`, and adds a root cron job that renews
  (~every 60 days) and reloads nginx.
  - The port-80 server **must keep** `location ^~ /.well-known/acme-challenge/ { root /var/www/acme; }`
    ahead of the HTTPS redirect. A server-level `return 301 https://…` (outside any
    `location`) runs before location matching and breaks issuing and renewal.
  - After switching from self-signed, a browser that earlier clicked "Proceed" can
    keep showing "Not secure" on open tabs. Test in a private window, or restart the browser.
  - `https://<ip>` still warns (the cert names the domain); always share the domain URL.
- **No catch-all `proxy_pass` to a backend that isn't there.** End every server
  block with `location / { return 404; }` so unknown paths fail instantly instead
  of timing out.
- **Redirect the bare paths people type or bookmark**, so they never fall through:
  ```nginx
  location = /        { return 302 /<default-app>/; }
  location = /<app>   { return 301 /<app>/; }                     # one per app
  location = /welcome { return 302 /<app>/welcome$is_args$args; }  # root-level SPA routes
  ```
- `opc` has passwordless sudo, so deploy steps can `sudo systemctl restart …`.

**Java / Maven (PowerShell)**
- Dotted `-D` args **must be single-quoted**: `'-Dmaven.test.skip=true'`.
- Use `-Dmaven.test.skip=true` (not `-DskipTests`) — the latter still *compiles*
  tests, and a repo may have a pre-existing broken test.
- PowerShell renders Maven/Angular **stderr warnings as a red "code 1"** — verify
  the *real* `$LASTEXITCODE` before assuming failure.

**Angular**
- `node_modules` may be **git-tracked and corrupt** → `rmdir` + fresh `npm install`
  (rmdir may hit *Access denied* on locked `.node/.exe`; install still succeeds).
- **Angular 17** has no `production` configuration name → build with plain
  `ng build --base-href /<app>/` (already prod). Output: `dist/<name>/`.
- **Angular 18** → `ng build --configuration production --base-href /<app>/`.
  Output: `dist/<name>/browser/`. Make deploy handle both (`browser/` fallback).
- Frontends must call **relative** `/api/...` in production (see §6.4).
- **Never navigate with a root-absolute URL** such as `window.location.href = '/login'`.
  It ignores `--base-href` and lands outside `/<app>/` (404, or 504 behind a
  catch-all). Use the Router (`router.navigate(['/login'])` respects the base
  href) or `new URL('login', document.baseURI).href`. The solar SSO page shipped
  with this bug.

---

## 4. Execution plan (order of operations)

1. **Scaffold Terraform** under `terraform/` (modules: `common, network, security,
   compute, nginx, mysql, monitoring`). Put a `versions.tf` pinning
   `oracle/oci` in **every module** (prevents the `hashicorp/oci` vs `oracle/oci`
   duplicate-provider bug).
2. Fill `terraform.tfvars` (gitignored) from §0.1. Set both instance shapes to
   `VM.Standard.E2.1.Micro`. `allowed_cidr_blocks = ["0.0.0.0/0"]` (or restrict SSH).
3. `terraform init && terraform validate && terraform apply`. MySQL ~21 min.
   If A1 → `Out of host capacity`, switch shapes to E2.1.Micro and re-apply.
4. `terraform output` → capture **public IP**, **private IP**, **mysql endpoint**.
5. On **both** boxes apply the §3 memory fixes and reboot; `free -m` must show
   ~945 MB total on each. Then install Java **before** starting any backend:
   `sudo dnf install -y --disablerepo='*' --enablerepo=ol9_baseos_latest,ol9_appstream java-21-openjdk-headless`.
6. Run **`terraform/deploy/app-bootstrap.sh`** on that box (env:
   `MYSQL_PWD=… JWT_SECRET=…`): creates `rp-app` user, `/opt/<app>` dirs, env files,
   systemd units, firewall rules, and the MySQL databases.
7. Run **`terraform/deploy/nginx-bootstrap.sh`** on that box
   (`APP_PRIVATE_IP=127.0.0.1 DOMAIN=<domain from §0.3>`): web roots, path-based
   reverse proxy, firewall, SELinux booleans/labels, and, when `DOMAIN` is set,
   a **trusted Let's Encrypt cert** (copy `enable-letsencrypt.sh` next to it; it is
   called automatically). Without `DOMAIN` you get a self-signed cert only. To add a
   domain later: `sudo DOMAIN=<domain> bash enable-letsencrypt.sh` on the nginx box.
8. **Convert each app to MySQL** (§6) and **build** (backend jar + Angular dist).
9. **Deploy** artifacts (jars → `/opt/<app>/<app>.jar` + restart service; Angular
   `dist` → `/var/www/<app>` + `chcon` + reload nginx).
10. **Verify** (§7). Then add the **CI/CD workflow** (§5) to each repo.

Reusable server-side scripts already exist in this repo:
`terraform/deploy/app-bootstrap.sh` and `terraform/deploy/nginx-bootstrap.sh`
(idempotent; nginx one won't clobber a deployed frontend).

---

## 5. CI/CD — GitHub Actions (`.github/workflows/deploy.yml` per repo)

Triggers on push to `main` **and** `master`. Steps: build backend
(`./mvnw -B -q '-Dmaven.test.skip=true' clean package`), build frontend
(`npm ci` then `ng build`), then SSH-deploy jar + Angular dist and restart.

**Required GitHub repo secrets** (Settings → Secrets and variables → Actions):
| Secret | Value |
|--------|-------|
| `SSH_PRIVATE_KEY` | contents of the deploy private key (`~/.ssh/rp-app-instances`) |
| `APP_HOST` | public IP of the runtime box |
| `NGINX_HOST` | same public IP (single-box) |

Angular build command differs by version (§3). Frontend `dist` path: try
`frontend/dist/<name>/browser` then fall back to `frontend/dist/<name>`.
Reference implementations already committed: `<app>/.github/workflows/deploy.yml`.

**CI deploys only copy artifacts and restart services**: no `dnf`, no provisioning.
This repo's `.github/workflows/ansible.yml` runs `site.yml`, which applies the
nginx template **and** `spring_boot.yml` (Java via full-repo `dnf`, `rp-app.jar`
on :8080). It is therefore **manual-only**; don't add a push trigger back.

---

## 6. App PostgreSQL → MySQL conversion checklist

Do this in **each** app repo/folder.

### 6.1 `pom.xml`
- **JPA/JDBC app:** remove `org.postgresql:postgresql`; add
  `com.mysql:mysql-connector-j` (runtime).
- **R2DBC (reactive) app:** remove `org.postgresql:r2dbc-postgresql` and
  `org.postgresql:postgresql`; add `io.asyncer:r2dbc-mysql:1.4.1` (runtime) **and**
  `com.mysql:mysql-connector-j` (runtime, for schema init). Works on Spring Boot 4.

### 6.2 `application.properties` (use env overrides so prod creds inject cleanly)
JPA/JDBC:
```
spring.datasource.url=${DB_URL:jdbc:mysql://localhost:3306/<db>}
spring.datasource.username=${DB_USERNAME:root}
spring.datasource.password=${DB_PASSWORD:root}
spring.datasource.driver-class-name=com.mysql.cj.jdbc.Driver
spring.jpa.hibernate.ddl-auto=update
spring.sql.init.platform=mysql
```
R2DBC (+ jdbc for schema init):
```
spring.r2dbc.url=${DB_R2DBC_URL:r2dbc:mysql://localhost:3306/<db>}
spring.r2dbc.username=${DB_USERNAME:root}
spring.r2dbc.password=${DB_PASSWORD:root}
spring.datasource.url=${DB_JDBC_URL:jdbc:mysql://localhost:3306/<db>}
spring.datasource.username=${DB_USERNAME:root}
spring.datasource.password=${DB_PASSWORD:root}
spring.sql.init.platform=mysql
```

### 6.3 `schema.sql` and `@Query` SQL — MySQL-ify
| PostgreSQL | MySQL |
|------------|-------|
| `BIGSERIAL` | `BIGINT AUTO_INCREMENT` |
| `TIMESTAMP` (column type) | `DATETIME` |
| `DEFAULT NOW()` | `DEFAULT CURRENT_TIMESTAMP` |
| `... ORDER BY col ASC NULLS LAST` | `... ORDER BY col IS NULL, col ASC` |
| `CAST(:x AS TIMESTAMP)` | `CAST(:x AS DATETIME)` (MySQL has no TIMESTAMP cast target) |
| `ILIKE` | `LOWER(col) LIKE LOWER(...)` |
| `RETURNING`, `jsonb`, `::type`, `text[]` | rewrite (no direct equivalent) |
- Fold Postgres `ALTER TABLE … ADD COLUMN` migrations into the `CREATE TABLE`,
  inline indexes as `KEY …`, and declare FKs table-level with `ON DELETE CASCADE`.
- **Grep the whole `src` tree** for `NULLS`, `AS TIMESTAMP`, `ILIKE`, `SERIAL`,
  `RETURNING`, `::`, `nativeQuery` before declaring done.

### 6.4 Frontend API base → relative in production
Make the API origin **empty/relative** when served behind the proxy (port 80/443),
and keep explicit `host:port` only for local dev. Pattern:
```ts
function originFor(devPort: string): string {
  if (typeof window === 'undefined' || !window.location) return `http://localhost:${devPort}`;
  const p = window.location.port;
  if (p === '' || p === '80' || p === '443') return ''; // same-origin (proxy routes it)
  return `${window.location.protocol}//${window.location.hostname}:${devPort}`;
}
```
So the app calls `/api/tasks`, `/api/jira/onload`, etc. — which nginx routes.

### 6.5 Build
- Backend: `.\mvnw.cmd -q '-Dmaven.test.skip=true' clean package` → `target/<app>-*.jar`.
- Frontend: §3 (version-specific `ng build`).

---

## 7. Verification checklist (via the domain, or the public IP if none)
```
openssl s_client -connect <domain>:443 -servername <domain> </dev/null | grep "Verify return code"
                               → Verify return code: 0 (ok), issuer Let's Encrypt
curl -I http://<domain>/<app>/ → 301 to https://<domain>/<app>/
sudo /root/.acme.sh/acme.sh --list   (on the nginx box) → domain listed with a renew date
sudo crontab -l | grep acme          → renewal cron present

GET /health                    → 200 "ok"
GET /<app>/                    → 200 (Angular index.html, correct <base href>)
GET /<app>/main*.js            → 200
GET /api/<prefix>/<endpoint>   → 200   (e.g. /api/jira/onload, /api/tasks/open)
GET /                          → 302 to /<default-app>/
GET /<app>                     → 301 to /<app>/
GET /no-such-path              → 404 immediately (never a 504)
```
On **every** box:
```
free -m                                          → Mem total ≈ 945 (≈ 498 = kdump still reserving)
cat /sys/kernel/kexec_crash_size                 → 0
systemctl is-enabled dnf-makecache.timer kdump   → disabled, disabled
```
- Backend logs: `journalctl -u <app>-backend` should show the MySQL JDBC/R2DBC URL
  and `Started …Application`.
- If an API 404s via nginx but 200s directly on `127.0.0.1:<port>`, it's the
  **trailing-slash location** bug (§3) — fix the nginx `location` prefix.

### 7.1 If you get `504 Gateway Time-out`
nginx is up but a backend didn't answer in time. Diagnose on the nginx box before
changing anything:

1. `sudo tail -n 20 /var/log/nginx/error.log` and read the `request:` and
   `upstream:` fields.
2. Match the message:

   | error.log says | Meaning | Fix |
   |---|---|---|
   | `upstream: "http://…:8080/…"`, or any port nothing serves | stale catch-all route | fix the nginx config (§3 nginx) |
   | `timed out … while connecting to upstream` | backend box not answering at all | box frozen (step 3), or NSG/firewalld blocking the port |
   | `timed out … while reading response header` | backend accepted but is stuck | box out of memory (step 3), or a request slower than `proxy_read_timeout` |
   | `connect() failed (111: Connection refused)` | a **502**, not a 504: backend down or still starting | `systemctl status` / `journalctl -u`; Spring Boot needs 60–90 s on a micro |

3. If SSH to the backend box hangs at `Connection timed out during banner exchange`,
   it is out of memory and thrashing. Reboot it from the OCI console, then check
   `sudo grep -iE 'out of memory|killed process' /var/log/messages | tail`,
   `free -m` and `/sys/kernel/kexec_crash_size`, and apply the §3 memory fixes.
4. Check which URL the browser really requests:
   `sudo tail -n 30 /var/log/nginx/access.log`. A bookmarked root-level route
   (`/welcome` instead of `/<app>/welcome`) needs a redirect (§3 nginx).

Don't "fix" a 504 by re-running Ansible or `dnf` on a live box: both make it worse.

---

## 8. Connecting to MySQL from a laptop (private DB)
MySQL has no public IP. Tunnel through the public box:
```
ssh -i <ssh_key> -N -L 13306:<mysql_fqdn>:3306 opc@<public_ip>
# then connect any client to 127.0.0.1:13306, user=<admin>, pass=<mysql_pw>
```
Or use MySQL Workbench "TCP/IP over SSH" (SSH host = public box, MySQL host = the
private FQDN / `10.0.2.x`).

---

## Appendix A — Concrete values from the last successful deployment (example)
> These are specifics of the current environment; a fresh run will differ.

- Region `ap-mumbai-1`; root compartment = tenancy OCID.
- Runtime box (ephemeral public IP) `137.23.42.212`; the other micro showed ~498 MB
  and was left unused. That was most likely the kdump reservation (§2 item 5), not
  a smaller box: reclaim it with the §3 fix.
- MySQL: `rpapp.private.rpapp.oraclevcn.com` / `10.0.2.16:3306`, DBs `jira`, `todo`.
- SSH deploy key: `~/.ssh/rp-app-instances`; login user `opc`; service user `rp-app`.
- **jira**: Spring Boot 4, JPA, port **5857**, controllers under `/api/jira` (+ `/api/auth`),
  Angular **18** (`dist/jira-frontend/browser`), base-href `/jira/`,
  repo `github.com/hershrana/jira.git` (private, branch `master`).
- **todo**: Spring Boot 4, **R2DBC**, port **5855**, paths `/api/tasks`,`/api/notes`,`/api/eod`,
  Angular **17** (`dist/todo-frontend`), base-href `/todo/`,
  repo `github.com/hershrana/todo.git` (private, branch `master`).

- revakunj prod domain: `hbr.publicvm.com` (free DNSExit name) → nginx box
  `137.23.57.203`, Let's Encrypt cert via acme.sh since 2026-09-22.

## Appendix B — Files this runbook relies on (already in this repo)
- `terraform/` — full IaC (modules with per-module `versions.tf`).
- `terraform/terraform.tfvars` — inputs (gitignored; fill from §0.1).
- `terraform/deploy/app-bootstrap.sh` — backend services + MySQL DBs (idempotent).
- `terraform/deploy/nginx-bootstrap.sh` — reverse proxy + SPAs (idempotent; `DOMAIN=` for real TLS).
- `terraform/deploy/enable-letsencrypt.sh` — Let's Encrypt cert + auto-renewal via acme.sh (idempotent).
- `<app>/.github/workflows/deploy.yml` — CI/CD per app.
- `DEPLOYMENT_GUIDE.md` — human-facing summary of the live setup.
