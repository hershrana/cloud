#!/usr/bin/env bash
# Issue a Let's Encrypt cert for DOMAIN with acme.sh (pure shell: no dnf/EPEL, safe on the
# 1 GB E2.1.Micro nginx box) and switch /etc/nginx/conf.d/rp-app.conf from the self-signed cert.
# Renewal: acme.sh cron (or systemd timer fallback) renews at ~60 days and reloads nginx.
# Prereqs: DOMAIN's A record points at this box's public IP; ports 80/443 open (NSG + firewalld).
# Usage (on the nginx box): sudo DOMAIN=hbr.publicvm.com bash enable-letsencrypt.sh
# nginx-bootstrap.sh calls this itself when DOMAIN is set. Idempotent.
set -euo pipefail

DOMAIN="${DOMAIN:?set DOMAIN}"
CONF=/etc/nginx/conf.d/rp-app.conf
WEBROOT=/var/www/acme
SSL_DIR=/etc/nginx/ssl
ACME_HOME=/root/.acme.sh
ACME="$ACME_HOME/acme.sh"

[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }

# 1. Serve ACME challenges over plain HTTP (port 80 otherwise redirects to https).
#    nginx-bootstrap.sh / the Ansible template already write this location; this only patches
#    hand-written configs whose port-80 server is a bare server-level "return 301 https://...".
mkdir -p "$WEBROOT/.well-known/acme-challenge"
restorecon -R "$WEBROOT" 2>/dev/null || true
if ! grep -q acme-challenge "$CONF"; then
  cp -a "$CONF" "$CONF.bak.$(date +%s)"
  # insert the challenge location right before the first "return 301 https" (the port-80 server)
  sed -i "0,/return 301 https/s||location ^~ /.well-known/acme-challenge/ { root $WEBROOT; default_type text/plain; }\n    location / { return 301 https://\$host\$request_uri; }\n    #return 301 https|" "$CONF"
  nginx -t
  systemctl reload nginx
fi

# 2. Install acme.sh (no email; Let's Encrypt doesn't require one)
if [ ! -x "$ACME" ]; then
  tmp=$(mktemp -d)
  curl -fsSL https://github.com/acmesh-official/acme.sh/archive/refs/heads/master.tar.gz | tar -xz -C "$tmp"
  (cd "$tmp"/acme.sh-master && ./acme.sh --install --home "$ACME_HOME" $(command -v crontab >/dev/null || echo --nocron))
  rm -rf "$tmp"
fi
"$ACME" --set-default-ca --server letsencrypt

# 3. Issue (exit code 2 = already issued and not due for renewal)
"$ACME" --issue -d "$DOMAIN" -w "$WEBROOT" --keylength ec-256 || [ $? -eq 2 ]

# 4. Install cert where nginx reads it; acme.sh re-runs this + reload on every renewal
"$ACME" --install-cert -d "$DOMAIN" --ecc \
  --key-file       "$SSL_DIR/$DOMAIN.key" \
  --fullchain-file "$SSL_DIR/$DOMAIN.crt" \
  --reloadcmd      "systemctl reload nginx"
chmod 600 "$SSL_DIR/$DOMAIN.key"
restorecon -R "$SSL_DIR" 2>/dev/null || true

# 5. Point nginx at the real cert
if ! grep -q "$SSL_DIR/$DOMAIN.crt" "$CONF"; then
  cp -a "$CONF" "$CONF.bak.$(date +%s)"
  sed -i -E "s|^(\s*ssl_certificate)\s+\S+;|\1     $SSL_DIR/$DOMAIN.crt;|; s|^(\s*ssl_certificate_key)\s+\S+;|\1 $SSL_DIR/$DOMAIN.key;|" "$CONF"
  grep -q ssl_protocols "$CONF" || sed -i "s|^\(\s*ssl_certificate_key .*\)$|\1\n    ssl_protocols TLSv1.2 TLSv1.3;|" "$CONF"
fi
nginx -t
systemctl reload nginx

# 6. Renewal fallback when there's no crontab: daily systemd timer
if ! command -v crontab >/dev/null; then
  cat > /etc/systemd/system/acme-renew.service <<EOF
[Unit]
Description=acme.sh renew
[Service]
Type=oneshot
ExecStart=$ACME --cron --home $ACME_HOME
EOF
  cat > /etc/systemd/system/acme-renew.timer <<EOF
[Unit]
Description=daily acme.sh renew
[Timer]
OnCalendar=*-*-* 03:17:00
RandomizedDelaySec=1h
Persistent=true
[Install]
WantedBy=timers.target
EOF
  systemctl daemon-reload
  systemctl enable --now acme-renew.timer
fi

echo "done: $("$ACME" --list | grep "$DOMAIN")"
