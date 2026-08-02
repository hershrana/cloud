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

- **Single-box runtime.** Always Free gives 2× AMD micro (~1 GB) or ARM A1
  (capacity-permitting). Run **nginx + all backends on ONE healthy box**; talk to
  MySQL over the private VCN. (See §3 for why one box.)
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
5. **Micro instances have ~1 GB and sometimes ~0.5 GB.** A ~0.5 GB box **cannot**
   run two JVMs and even OOM-thrashes during `dnf install java` (SSH banner
   timeouts). Pick the box that reports the most RAM (`free -m`) for runtime.
6. **Public IPs are ephemeral** — they change if an instance is recreated. Update
   GitHub secrets after any recreate, or reserve a static public IP.

---

## 3. Gotchas learned the hard way (apply these preemptively)

**Cloud-init / OS**
- In cloud-init: **create a 2 GB swapfile FIRST**, then install packages. Do **not**
  run `dnf update -y` on a 1 GB box (it OOM-wedges the instance). Only
  `dnf install -y <needed>`.
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
5. Pick the healthier box (`ssh … "free -m"`), install Java there:
   `sudo dnf install -y java-21-openjdk-headless`.
6. Run **`terraform/deploy/app-bootstrap.sh`** on that box (env:
   `MYSQL_PWD=… JWT_SECRET=…`): creates `rp-app` user, `/opt/<app>` dirs, env files,
   systemd units, firewall rules, and the MySQL databases.
7. Run **`terraform/deploy/nginx-bootstrap.sh`** on that box
   (`APP_PRIVATE_IP=127.0.0.1`): web roots, path-based reverse proxy, firewall,
   SELinux booleans/labels.
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

## 7. Verification checklist (all should be 200 via the public IP)
```
GET /health                    → 200 "ok"
GET /<app>/                    → 200 (Angular index.html, correct <base href>)
GET /<app>/main*.js            → 200
GET /api/<prefix>/<endpoint>   → 200   (e.g. /api/jira/onload, /api/tasks/open)
```
- Backend logs: `journalctl -u <app>-backend` should show the MySQL JDBC/R2DBC URL
  and `Started …Application`.
- If an API 404s via nginx but 200s directly on `127.0.0.1:<port>`, it's the
  **trailing-slash location** bug (§3) — fix the nginx `location` prefix.

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
- Runtime box (ephemeral public IP) `137.23.42.212`; the other micro (~498 MB) left unused.
- MySQL: `rpapp.private.rpapp.oraclevcn.com` / `10.0.2.16:3306`, DBs `jira`, `todo`.
- SSH deploy key: `~/.ssh/rp-app-instances`; login user `opc`; service user `rp-app`.
- **jira**: Spring Boot 4, JPA, port **5857**, controllers under `/api/jira` (+ `/api/auth`),
  Angular **18** (`dist/jira-frontend/browser`), base-href `/jira/`,
  repo `github.com/hershrana/jira.git` (private, branch `master`).
- **todo**: Spring Boot 4, **R2DBC**, port **5855**, paths `/api/tasks`,`/api/notes`,`/api/eod`,
  Angular **17** (`dist/todo-frontend`), base-href `/todo/`,
  repo `github.com/hershrana/todo.git` (private, branch `master`).

## Appendix B — Files this runbook relies on (already in this repo)
- `terraform/` — full IaC (modules with per-module `versions.tf`).
- `terraform/terraform.tfvars` — inputs (gitignored; fill from §0.1).
- `terraform/deploy/app-bootstrap.sh` — backend services + MySQL DBs (idempotent).
- `terraform/deploy/nginx-bootstrap.sh` — reverse proxy + SPAs (idempotent).
- `<app>/.github/workflows/deploy.yml` — CI/CD per app.
- `DEPLOYMENT_GUIDE.md` — human-facing summary of the live setup.
