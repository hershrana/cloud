#!/usr/bin/env bash
# Nginx-box bootstrap: web roots for both SPAs + reverse proxy to backends.
set -euo pipefail

APP_PRIVATE_IP="${APP_PRIVATE_IP:?set APP_PRIVATE_IP}"
JIRA_PORT="5857"
TODO_PORT="5855"

echo "== Ensuring nginx installed =="
command -v nginx >/dev/null 2>&1 || sudo dnf install -y nginx

echo "== Creating web roots =="
sudo mkdir -p /var/www/jira /var/www/todo
# Placeholder pages only if nothing deployed yet (never clobber a real deploy)
[ -e /var/www/jira/index.html ] || echo '<h1>Jira frontend not deployed yet</h1>' | sudo tee /var/www/jira/index.html >/dev/null
[ -e /var/www/todo/index.html ] || echo '<h1>Todo frontend not deployed yet</h1>' | sudo tee /var/www/todo/index.html >/dev/null
sudo chmod -R 755 /var/www

echo "== Writing nginx site config =="
sudo tee /etc/nginx/conf.d/rp-app.conf >/dev/null <<EOF
server {
    listen 80 default_server;
    server_name _;

    # Health check
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
        proxy_pass http://${APP_PRIVATE_IP}:${JIRA_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 120s;
    }
    location /api/auth {
        proxy_pass http://${APP_PRIVATE_IP}:${JIRA_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 120s;
    }

    # ---- Todo backend (/api/tasks, /api/notes, /api/eod) — prefix preserved ----
    location /api/tasks {
        proxy_pass http://${APP_PRIVATE_IP}:${TODO_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 120s;
    }
    location /api/notes {
        proxy_pass http://${APP_PRIVATE_IP}:${TODO_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 120s;
    }
    location /api/eod {
        proxy_pass http://${APP_PRIVATE_IP}:${TODO_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 120s;
    }

    location = / {
        return 302 /jira/;
    }
}
EOF

# Remove default server block if present (avoids duplicate default_server)
if [ -f /etc/nginx/nginx.conf ] && grep -q 'default_server' /etc/nginx/nginx.conf; then
  sudo sed -i 's/listen\(.*\)default_server/listen\1/g' /etc/nginx/nginx.conf || true
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
