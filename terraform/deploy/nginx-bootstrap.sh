#!/usr/bin/env bash
# Nginx-box bootstrap: web roots for both SPAs + reverse proxy to backends.
set -euo pipefail

APP_PRIVATE_IP="${APP_PRIVATE_IP:?set APP_PRIVATE_IP}"
JIRA_PORT="5857"
TODO_PORT="5855"
# Per-backend upstream hosts (permanent fix: one JVM per box so a 1 GB micro
# never has to hold two JVMs). Jira backend stays local on the nginx box; Todo
# backend runs on the dedicated app box. Override via env when topology changes.
JIRA_HOST="${JIRA_HOST:-${APP_PRIVATE_IP}}"
TODO_HOST="${TODO_HOST:-10.0.1.217}"

echo "== Ensuring nginx installed =="
command -v nginx >/dev/null 2>&1 || sudo dnf install -y nginx

echo "== Creating web roots =="
sudo mkdir -p /var/www/jira /var/www/todo
# Placeholder pages only if nothing deployed yet (never clobber a real deploy)
[ -e /var/www/jira/index.html ] || echo '<h1>Jira frontend not deployed yet</h1>' | sudo tee /var/www/jira/index.html >/dev/null
[ -e /var/www/todo/index.html ] || echo '<h1>Todo frontend not deployed yet</h1>' | sudo tee /var/www/todo/index.html >/dev/null
sudo chmod -R 755 /var/www

echo "== Writing nginx site config =="
echo "== Generating self-signed TLS certificate (if missing) =="
command -v openssl >/dev/null 2>&1 || sudo dnf install -y openssl
sudo mkdir -p /etc/nginx/ssl
if [ ! -f /etc/nginx/ssl/selfsigned.crt ]; then
  if [ -n "${PUBLIC_IP:-}" ]; then
    sudo openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
      -keyout /etc/nginx/ssl/selfsigned.key -out /etc/nginx/ssl/selfsigned.crt \
      -subj "/CN=${PUBLIC_IP}" -addext "subjectAltName=IP:${PUBLIC_IP}"
  else
    sudo openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
      -keyout /etc/nginx/ssl/selfsigned.key -out /etc/nginx/ssl/selfsigned.crt \
      -subj "/CN=rp-app"
  fi
  sudo chmod 600 /etc/nginx/ssl/selfsigned.key
fi

echo "== Writing nginx location include =="
sudo tee /etc/nginx/rp-app-locations.inc >/dev/null <<EOF
    location = /health {
        add_header Content-Type text/plain;
        return 200 'ok';
    }

    # ---- Jira SPA ----
    location /jira/ {
        alias /var/www/jira/;
        try_files \$uri \$uri/ /jira/index.html;
    }

    # ---- Todo SPA ----
    location /todo/ {
        alias /var/www/todo/;
        try_files \$uri \$uri/ /todo/index.html;
    }

    # ---- Jira backend (context path /api/jira, plus /api/auth) — prefix preserved ----
    location /api/jira {
        proxy_pass http://${JIRA_HOST}:${JIRA_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 30s;
    }
    location /api/auth {
        proxy_pass http://${JIRA_HOST}:${JIRA_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 30s;
    }
    location /api/allocation {
        proxy_pass http://${JIRA_HOST}:${JIRA_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 30s;
    }

    # ---- Todo backend (/api/jira-worklog, /api/tasks, /api/notes, /api/eod) — prefix preserved ----
    # NOTE: /api/jira-worklog is a longer prefix than /api/jira, so it wins and
    # correctly routes to the todo backend (not the jira backend).
    location /api/jira-worklog {
        proxy_pass http://${TODO_HOST}:${TODO_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 30s;
    }
    location /api/tasks {
        proxy_pass http://${TODO_HOST}:${TODO_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 30s;
    }
    location /api/notes {
        proxy_pass http://${TODO_HOST}:${TODO_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 30s;
    }
    location /api/eod {
        proxy_pass http://${TODO_HOST}:${TODO_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 30s;
    }

    location = / {
        return 302 /jira/;
    }
EOF

echo "== Writing nginx site config (HTTP->HTTPS redirect + TLS) =="
sudo tee /etc/nginx/conf.d/rp-app.conf >/dev/null <<EOF
server {
    listen 80 default_server;
    server_name _;

    # Plain-HTTP health check stays available; everything else redirects to HTTPS
    location = /health {
        add_header Content-Type text/plain;
        return 200 'ok';
    }
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl default_server;
    server_name _;

    ssl_certificate     /etc/nginx/ssl/selfsigned.crt;
    ssl_certificate_key /etc/nginx/ssl/selfsigned.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    include /etc/nginx/rp-app-locations.inc;
}
EOF

# Remove the stock default server block (root /usr/share/nginx/html) so it does
# not collide with our default_server on 80/443 ("conflicting server name _"),
# and so internet scanners stop resolving against /usr/share/nginx/html.
if [ -f /etc/nginx/nginx.conf ] && grep -q '/usr/share/nginx/html' /etc/nginx/nginx.conf; then
  sudo cp -n /etc/nginx/nginx.conf /etc/nginx/nginx.conf.orig 2>/dev/null || true
  sudo awk '
    function flush(){ if (buf !~ /\/usr\/share\/nginx\/html/) printf "%s", buf; buf=""; inblk=0; depth=0 }
    {
      if (!inblk && $0 ~ /^[[:space:]]*server[[:space:]]*\{[[:space:]]*$/) { inblk=1; depth=0; buf="" }
      if (inblk) {
        buf = buf $0 ORS
        depth += gsub(/\{/, "{") - gsub(/\}/, "}")
        if (depth <= 0) flush()
        next
      }
      print
    }
  ' /etc/nginx/nginx.conf | sudo tee /etc/nginx/nginx.conf.new >/dev/null
  sudo mv /etc/nginx/nginx.conf.new /etc/nginx/nginx.conf
fi

# SELinux: allow nginx to make outbound proxy connections + read /var/www
sudo setsebool -P httpd_can_network_connect 1 2>/dev/null || true
sudo chcon -R -t httpd_sys_content_t /var/www 2>/dev/null || true

sudo nginx -t
sudo systemctl enable nginx >/dev/null 2>&1 || true
sudo systemctl restart nginx

echo "== Opening firewall for HTTP/HTTPS =="
sudo firewall-cmd --permanent --add-service=http --add-service=https 2>/dev/null || true
sudo firewall-cmd --reload 2>/dev/null || true
echo "== Done =="
