# Learning module: one-time OCI setup (revakunj)

The revakunj repo adds a third app, **Learning**:

| Part | What | Where it runs |
|---|---|---|
| Backend | `backend/learning` Spring Boot jar, port **5902**, systemd `revakunj-learning` | `LEARNING_HOST` (you choose, step 1) |
| Frontend | Angular SPA under `https://hbr.publicvm.com/learning/` | nginx box, `/var/www/learning` |
| API | `https://hbr.publicvm.com/learning/api/*` → backend `/api/*` | nginx proxies to the backend |
| DB | Flyway `V200`/`V201` in the shared `kids_money_game` schema, applied by the app on first start | MySQL HeatWave (no manual SQL) |

The GitHub deploy job (revakunj `.github/workflows/deploy.yml`) builds and ships all of this on
every push to `master`. It does **not** create the systemd unit, the directories, the nginx
routes or the network rule. Do the steps below **once, before merging** the Learning PR. If you
don't, that deploy fails at the `deploy learning` step and the frontends are not updated.

Current layout, from `scripts/wsl-deploy-nginx.sh`:

| Box | Public IP | Private IP | Runs today |
|---|---|---|---|
| nginx box | `137.23.57.203` | - | nginx + solar (5901) |
| app box | `92.4.94.109` | `10.0.1.85` | kids (5900) |

Both are `VM.Standard.E2.1.Micro` (1 GB). `AI_DEPLOYMENT_RUNBOOK.md` §1 says **one JVM per
micro box**, so Learning is a second JVM on one of them. That only works if the box has the
memory. Step 1 decides which box.

---

## 1. Measure memory and choose the box

Run on **both** boxes:

```bash
free -m                                    # look at "available"
swapon --show                              # is there any swap?
cat /sys/kernel/kexec_crash_size           # should be 0 after the runbook §3 fix
ps -o rss=,args= -C java | awk '{printf "%d MB  %s\n", $1/1024, $NF}'
```

Each backend runs with `-Xmx192m` and uses about **250-320 MB** of RSS once warm. Learning is idle
most of the time but has the same footprint.

| If… | Then |
|---|---|
| `kexec_crash_size` isn't 0, or `free -m` total is ~500 MB | Apply `AI_DEPLOYMENT_RUNBOOK.md` §3 (kdump + dnf fixes) and reboot first |
| a box shows **≥ 400 MB available** | It can take Learning. Prefer the **app box**: it doesn't also run nginx or acme.sh |
| neither box has 400 MB | Add swap (step 2) and re-measure, or put Learning on a new A1/third instance (out of scope here) |

Write down your choice:

- **Option A: app box** (recommended). `LEARNING_HOST` = `92.4.94.109`. nginx proxies to
  `10.0.1.85:5902`. Needs the Terraform network rule in step 3c.
- **Option B: nginx box.** `LEARNING_HOST` = nginx box (the default). nginx proxies to
  `127.0.0.1:5902`. No network change.

## 2. Add 1 GB swap on the chosen box (safety net)

Two JVMs on 1 GB can hit the OOM killer during a restart, when both are warming up. Swap turns
that into a slow minute instead of a wedged box:

```bash
if ! swapon --show | grep -q /swapfile; then
  sudo fallocate -l 1G /swapfile && sudo chmod 600 /swapfile
  sudo mkswap /swapfile && sudo swapon /swapfile
  echo '/swapfile none swap defaults 0 0' | sudo tee -a /etc/fstab
  echo 'vm.swappiness=10' | sudo tee /etc/sysctl.d/99-swappiness.conf && sudo sysctl -p /etc/sysctl.d/99-swappiness.conf
fi
free -m
```

## 3. Change the scripts in this repo

### 3a. `revakunj/app-bootstrap-revakunj.sh`: add learning to the port and jar maps

```diff
-declare -A PORT=([kids]=5900 [solar]=5901) JAR=([kids]=kids-money-game [solar]=solar-ev-tracker)
-APPS="${APPS:?set APPS to kids and/or solar}"
+declare -A PORT=([kids]=5900 [solar]=5901 [learning]=5902) \
+           JAR=([kids]=kids-money-game [solar]=solar-ev-tracker [learning]=learning)
+APPS="${APPS:?set APPS to the apps on this box, e.g. \"kids learning\" or \"solar learning\"}"
```

The unit, env file, firewalld rule (port from `10.0.0.0/16`) and sudoers entry are then created
for learning exactly like the others.

### 3b. `revakunj/nginx-revakunj.inc` and `revakunj/nginx-bootstrap-revakunj.sh`

Append to `nginx-revakunj.inc`:

```nginx
    location /learning/ {
        alias /var/www/learning/;
        try_files $uri $uri/ /learning/index.html;
    }
    location /learning/api/ {
        proxy_pass http://LEARNING_HOST:5902/api/;
        # Admins upload course HTML files up to 10 MB
        client_max_body_size 12m;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        # Same-origin SPA; don't forward Origin (see the kids/solar blocks)
        proxy_set_header Origin "";
        proxy_read_timeout 60s;
    }
```

In `nginx-bootstrap-revakunj.sh`:

```diff
-#   KIDS_HOST=10.0.1.85 SOLAR_HOST=127.0.0.1 bash nginx-bootstrap-revakunj.sh
+#   KIDS_HOST=10.0.1.85 SOLAR_HOST=127.0.0.1 LEARNING_HOST=10.0.1.85 bash nginx-bootstrap-revakunj.sh
 set -euo pipefail
-: "${KIDS_HOST:?}" "${SOLAR_HOST:?}"
+: "${KIDS_HOST:?}" "${SOLAR_HOST:?}" "${LEARNING_HOST:?}"
@@
-sudo mkdir -p /var/www/kids /var/www/solar
-sudo chown opc:opc /var/www/kids /var/www/solar
+sudo mkdir -p /var/www/kids /var/www/solar /var/www/learning
+sudo chown opc:opc /var/www/kids /var/www/solar /var/www/learning
 [ -e /var/www/kids/index.html ]  || echo '<h1>kids not deployed yet</h1>'  > /var/www/kids/index.html
 [ -e /var/www/solar/index.html ] || echo '<h1>solar not deployed yet</h1>' > /var/www/solar/index.html
-sudo chcon -R -t httpd_sys_content_t /var/www/kids /var/www/solar
+[ -e /var/www/learning/index.html ] || echo '<h1>learning not deployed yet</h1>' > /var/www/learning/index.html
+sudo chcon -R -t httpd_sys_content_t /var/www/kids /var/www/solar /var/www/learning
@@
-sed -e "s/KIDS_HOST/$KIDS_HOST/g" -e "s/SOLAR_HOST/$SOLAR_HOST/g" "${INC_SRC:-/tmp/nginx-revakunj.inc}" | sudo tee $INC >/dev/null
+sed -e "s/KIDS_HOST/$KIDS_HOST/g" -e "s/SOLAR_HOST/$SOLAR_HOST/g" -e "s/LEARNING_HOST/$LEARNING_HOST/g" \
+  "${INC_SRC:-/tmp/nginx-revakunj.inc}" | sudo tee $INC >/dev/null
@@
-echo "nginx: /kids -> $KIDS_HOST:5900, /solar -> $SOLAR_HOST:5901"
+echo "nginx: /kids -> $KIDS_HOST:5900, /solar -> $SOLAR_HOST:5901, /learning -> $LEARNING_HOST:5902"
```

### 3c. Option A only: `terraform/modules/security/main.tf`, open 5902 from nginx to the app box

The NSG currently allows only **5900** from the nginx NSG. Add a rule below
`compute_revakunj_ingress`:

```hcl
# Allow revakunj learning backend (5902) from Nginx NSG
resource "oci_core_network_security_group_security_rule" "compute_revakunj_learning_ingress" {
  network_security_group_id = oci_core_network_security_group.compute.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = oci_core_network_security_group.nginx.id
  source_type               = "NETWORK_SECURITY_GROUP"

  tcp_options {
    destination_port_range {
      min = 5902
      max = 5902
    }
  }
}
```

```bash
cd terraform && terraform plan    # expect exactly: 1 to add, 0 to change, 0 to destroy
terraform apply
```

If the plan shows anything else, stop. The state has drifted, and you should sort that out first.

### 3d. `revakunj/github-workflow/deploy.yml`

This is a mirror of the revakunj repo's workflow. Copy the new version over it after the
Learning PR merges, so the two stay identical.

## 4. Run the bootstraps on the boxes

Copy the updated scripts up first (`scp revakunj/*.sh revakunj/nginx-revakunj.inc opc@<box>:/tmp/`).

**On the box that will run Learning.** List **every** app on that box, because the script
rewrites `/etc/sudoers.d/revakunj` from `APPS`. Leaving one out removes the deploy user's
right to restart it.

```bash
# Option A (app box)
APPS="kids learning"  bash /tmp/app-bootstrap-revakunj.sh
# Option B (nginx box)
APPS="solar learning" bash /tmp/app-bootstrap-revakunj.sh

sudo cat /etc/sudoers.d/revakunj          # must list every app on this box
systemctl cat revakunj-learning | head -12
```

**On the nginx box** (always, for either option):

```bash
# Option A
KIDS_HOST=10.0.1.85 SOLAR_HOST=127.0.0.1 LEARNING_HOST=10.0.1.85 INC_SRC=/tmp/nginx-revakunj.inc \
  bash /tmp/nginx-bootstrap-revakunj.sh
# Option B
KIDS_HOST=10.0.1.85 SOLAR_HOST=127.0.0.1 LEARNING_HOST=127.0.0.1 INC_SRC=/tmp/nginx-revakunj.inc \
  bash /tmp/nginx-bootstrap-revakunj.sh

curl -sk https://hbr.publicvm.com/learning/ | head -1   # "learning not deployed yet"
```

**Option A only.** Check that nginx can reach the app box on 5902. Expect `Connection refused`
(the port is reachable but nothing is running yet), **not** a timeout:

```bash
curl -s -m 5 http://10.0.1.85:5902/api/health; echo "exit=$?"   # exit=7 good, exit=28 (timeout) = NSG/firewalld not open
```

## 5. Point the deploy job at the box (Option A only)

The revakunj workflow reads `LEARNING_HOST` from a repo **variable**, falling back to the nginx
box:

```bash
gh variable set LEARNING_HOST --body 92.4.94.109 -R hershrana/revakunj
gh variable list -R hershrana/revakunj
```

`SSH_KNOWN_HOSTS` already pins both boxes, so no secret changes are needed.

## 6. Merge and watch the first deploy

Merge the Learning PR in revakunj, then:

```bash
gh run watch -R hershrana/revakunj            # "Deploy to OCI"
```

It should end with `ok /learning/` and `ok /learning/api/health`. Then check:

```bash
curl -s https://hbr.publicvm.com/learning/api/health          # {"status":"UP"}
ssh opc@<LEARNING_HOST> 'free -m; systemctl is-active revakunj-learning; \
  sudo journalctl -u revakunj-learning -n 30 --no-pager | grep -E "Migrating|Successfully applied|Started"'
```

The first start logs `Migrating schema kids_money_game to version "200 - learning schema"` and
`"201 - learning course seed"`. Recheck `free -m` a few minutes later. If `available` has dropped
below about 100 MB and swap use keeps growing, move Learning to the other box. The deploy job
only needs `LEARNING_HOST` and the nginx `proxy_pass` changed.

## 7. Turn it on for people

1. Everyone who was signed in before the deploy must **sign out and in again**. Tokens carry
   permissions, and old tokens don't have `LEARNING_*`.
2. Kids app → **User management**: give learners the `LEARNING_USER` role. `ADMIN` already has
   `LEARNING_COURSE_MANAGE`.
3. Welcome page → **Learning** tile → **Manage** → *Manager Software Engineering @ Mastercard*
   → upload `index.html` (software_manager repo) → **Review & publish** → set the course to
   **PUBLISHED**.

## Rollback

- **App only** (keeps data): `ssh opc@<LEARNING_HOST> 'sudo systemctl disable --now revakunj-learning'`.
  nginx then returns 502 on `/learning/api/`, and nothing else is affected.
- **Remove the routes**: delete the two `/learning` blocks from `/etc/nginx/rp-revakunj-locations.inc`,
  then `sudo nginx -t && sudo systemctl reload nginx`.
- **Database**: nothing to undo for other apps. The `learning_*` tables and `LEARNING_*`
  permissions are additive. Kids and solar ignore `V200+` in the shared Flyway history (solar
  needs the revakunj commit that adds `*:future` to its `ignore-migration-patterns`, which is
  part of the Learning PR).

## Troubleshooting

| Symptom | Likely cause | Check |
|---|---|---|
| Deploy fails at `deploy learning` with `No such file or directory` | Step 4 not run on `LEARNING_HOST` | `ls -ld /opt/revakunj/learning` |
| Deploy fails at `sudo systemctl restart revakunj-learning` | sudoers missing learning, or the bootstrap ran with the wrong `APPS` | `sudo cat /etc/sudoers.d/revakunj` |
| `/learning/api/` gives **504** | Option A network not open (NSG 3c or firewalld), or the box is out of memory | step 4 `curl` test; `free -m` |
| `/learning/api/` gives **502** | Backend down or still starting (60-90 s on a micro) | `journalctl -u revakunj-learning -n 80` |
| Upload fails with **413** | nginx `client_max_body_size` missing from the `/learning/api/` block | the `.inc` file on the box |
| SSH to the box hangs at "banner exchange" | Out of memory | Reboot from the OCI console, then see step 1/2 or move Learning |
| Learning tile or `/learning/` shows but the API says 401/403 | Old token without `LEARNING_*` | Sign out and in again |
