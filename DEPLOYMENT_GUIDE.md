# Auto-Deploy Setup (CI/CD) — Jira & Todo on OCI Always Free

Whenever you push to `main`/`master` in either repo, GitHub Actions builds the app
(backend jar + Angular frontend) and deploys it to the OCI server automatically.

---

## 1. What is running where

Everything runs on **one healthy Always-Free VM** (the other 498 MB micro was too
small to run two JVMs, so it is currently unused/spare):

| Component            | Location                                   |
|----------------------|--------------------------------------------|
| Nginx (reverse proxy + static SPAs) | Server `137.23.42.212` (public)     |
| Jira backend (Spring Boot)          | same box, `127.0.0.1:5857`, systemd `jira-backend` |
| Todo backend (Spring Boot)          | same box, `127.0.0.1:5855`, systemd `todo-backend` |
| MySQL HeatWave (`jira`, `todo` DBs) | `rpapp.private.rpapp.oraclevcn.com:3306` (private) |

### Live URLs (already working)
- Jira UI:  http://137.23.42.212/jira/
- Todo UI:  http://137.23.42.212/todo/
- Health:   http://137.23.42.212/health
- Jira API: http://137.23.42.212/api/jira/... (also `/api/auth/...`)
- Todo API: http://137.23.42.212/api/tasks/..., `/api/notes/...`, `/api/eod/...`

Nginx routes by path prefix to the correct backend; the frontends call these
relative `/api/...` paths automatically when served over port 80.

---

## 2. One-time GitHub setup (do this in BOTH repos: `jira` and `todo`)

Go to the repo on GitHub → **Settings** → **Secrets and variables** → **Actions**
→ **New repository secret**, and add these three secrets:

| Secret name       | Value                                             |
|-------------------|---------------------------------------------------|
| `APP_HOST`        | `137.23.42.212`                                   |
| `NGINX_HOST`      | `137.23.42.212`                                   |
| `SSH_PRIVATE_KEY` | (contents of the private key — see below)         |

### How to get the `SSH_PRIVATE_KEY` value
Run this locally and paste the **entire** output (including the
`-----BEGIN ...-----` / `-----END ...-----` lines) as the secret value:

```powershell
Get-Content "$HOME\.ssh\rp-app-instances" -Raw
```

> Treat this key as a password. It is the deploy key for the server. Do **not**
> commit it to the repo — it only lives in GitHub Secrets.

---

## 3. Push the changes that are already made

The following files were created/modified locally and must be committed & pushed.

### `jira` repo
- `.github/workflows/deploy.yml` (new — the pipeline)
- `pom.xml` (PostgreSQL → MySQL connector)
- `src/main/resources/application.properties` (MySQL datasource + env overrides)
- `src/main/resources/schema.sql` (MySQL syntax)
- `frontend/src/app/services/jira.service.ts` (already used relative `/api/jira` in prod — unchanged behaviour)

### `todo` repo
- `.github/workflows/deploy.yml` (new — the pipeline)
- `pom.xml` (r2dbc-postgresql → r2dbc-mysql + mysql-connector-j)
- `src/main/resources/application.properties` (MySQL r2dbc/jdbc + env overrides)
- `src/main/resources/schema.sql` (MySQL syntax)
- `src/main/java/org/example/todo/repo/TaskRepository.java` (`NULLS LAST` → `IS NULL, ... ASC`; `CAST(... AS TIMESTAMP)` → `AS DATETIME`)
- `frontend/src/app/task.service.ts` (hardcoded `:5855/:5857/:5588` origins → same-origin relative in prod)

Example:
```powershell
cd C:\upi\jira
git add .github/workflows/deploy.yml pom.xml src/main/resources/application.properties src/main/resources/schema.sql frontend/src/app/services/jira.service.ts
git commit -m "MySQL migration + auto-deploy pipeline"
git push

cd C:\upi\todo\todo
git add .github/workflows/deploy.yml pom.xml src/main/resources/application.properties src/main/resources/schema.sql src/main/java/org/example/todo/repo/TaskRepository.java frontend/src/app/task.service.ts
git commit -m "MySQL migration + auto-deploy pipeline"
git push
```

The push to `main` triggers the workflow. Watch it under the repo's **Actions** tab.

---

## 4. How the pipeline works (`.github/workflows/deploy.yml`)

On push to `main`/`master`:
1. Checkout code.
2. Build backend: `./mvnw -Dmaven.test.skip=true clean package`.
3. Build frontend: `npm ci` then `ng build --base-href /jira/` (or `/todo/`).
4. SSH deploy:
   - copy the jar to the server, `systemctl restart` the backend service;
   - copy the frontend `dist` to `/var/www/jira` (or `/var/www/todo`), reload nginx.

Tests are skipped (`-Dmaven.test.skip=true`) because the Jira repo has one
pre-existing broken test.

---

## 5. Server credentials / config (already applied on the box)

- Backend env files: `/opt/jira/env`, `/opt/todo/env` (DB URL/user/pass, JWT secret, `-Xmx192m`).
- DB user `admin`, DBs `jira` & `todo` on MySQL HeatWave.
- systemd services: `jira-backend`, `todo-backend` (auto-restart, enabled on boot).
- Firewall: HTTP/HTTPS open; backend ports 5855–5857 open only inside the VCN.
- SELinux: nginx allowed to proxy and to read `/var/www`.

### Useful server commands
```bash
ssh -i "$HOME/.ssh/rp-app-instances" opc@137.23.42.212
sudo systemctl status jira-backend todo-backend nginx
sudo journalctl -u jira-backend -f
sudo journalctl -u todo-backend -f
```

---

## 6. Manual redeploy (without git push)

```powershell
# Backend
scp -i "$HOME\.ssh\rp-app-instances" C:\upi\jira\target\jira-0.0.1-SNAPSHOT.jar opc@137.23.42.212:/tmp/jira.jar
ssh -i "$HOME\.ssh\rp-app-instances" opc@137.23.42.212 "sudo mv /tmp/jira.jar /opt/jira/jira.jar && sudo chown rp-app:rp-app /opt/jira/jira.jar && sudo systemctl restart jira-backend"
```

Re-run the server bootstrap scripts anytime (idempotent):
`terraform/deploy/app-bootstrap.sh` and `terraform/deploy/nginx-bootstrap.sh`.

---

## 7. Notes / limitations

- The IPs (`137.23.42.212`) are ephemeral public IPs; if the instance is
  recreated they change and the GitHub secrets must be updated. (Reserve a
  static public IP in OCI to avoid this.)
- Only HTTP (port 80) is configured. Add TLS (Let's Encrypt / OCI cert) for HTTPS.
- The second micro instance (`137.23.41.69`, ~498 MB) is unused — you can
  terminate it in OCI to reduce clutter, or keep it as a spare.
