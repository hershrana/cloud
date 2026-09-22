#!/usr/bin/env bash
# Sets the revakunj deploy secrets in GitHub Actions. Values are read locally and
# piped straight to `gh secret set`; nothing is echoed or written to disk.
# Needs: gh CLI logged in (gh auth login) with admin rights on the repo.
# Run from the repo root:  bash revakunj/set-github-secrets.sh
set -euo pipefail
REPO=hershrana/revakunj

db_pw=$(sed -nE 's/^\s*mysql_admin_password\s*=\s*"([^"]*)".*/\1/p' terraform/terraform.tfvars | tr -d '\r')
[ -n "$db_pw" ] || { echo "mysql_admin_password not found in terraform/terraform.tfvars"; exit 1; }

gh secret set SSH_PRIVATE_KEY -R $REPO < ~/.ssh/revakunj_deploy
gh secret set SSH_KNOWN_HOSTS -R $REPO < ~/.ssh/revakunj_known_hosts
gh secret set APP_HOST        -R $REPO --body 92.4.94.109
gh secret set NGINX_HOST      -R $REPO --body 137.23.57.203
gh secret set DB_USERNAME     -R $REPO --body admin
printf '%s' "$db_pw" | gh secret set DB_PASSWORD -R $REPO
# Fresh HS512 key, generated here and never stored locally
openssl rand -base64 64 | tr -d '\n' | gh secret set JWT_SECRET -R $REPO
gh secret list -R $REPO
