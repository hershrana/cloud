#!/usr/bin/env bash
# cloud-init: install Nginx and configure reverse proxy to Spring Boot backend
set -euo pipefail

# Swap first so the 1 GB micro instance doesn't OOM during installs.
if [ ! -f /swapfile ]; then
  fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

dnf install -y nginx

cat > /etc/nginx/conf.d/rp-app.conf <<'NGINX'
upstream backend {
    server ${backend_ip}:${backend_port};
    keepalive 32;
}

server {
    listen 80;
    server_name _;

    location / {
        proxy_pass         http://backend;
        proxy_http_version 1.1;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_connect_timeout 10s;
        proxy_read_timeout    60s;
    }

    location /health {
        access_log off;
        return 200 "OK\n";
        add_header Content-Type text/plain;
    }
}
NGINX

systemctl enable --now nginx
