#!/usr/bin/env bash
# Run ON THE NGINX BOX once (idempotent), with nginx-revakunj.inc copied to /tmp:
#   KIDS_HOST=10.0.1.85 SOLAR_HOST=127.0.0.1 bash nginx-bootstrap-revakunj.sh
set -euo pipefail
: "${KIDS_HOST:?}" "${SOLAR_HOST:?}"
CONF=/etc/nginx/conf.d/rp-app.conf
INC=/etc/nginx/rp-revakunj-locations.inc

sudo mkdir -p /var/www/kids /var/www/solar
sudo chown opc:opc /var/www/kids /var/www/solar
[ -e /var/www/kids/index.html ]  || echo '<h1>kids not deployed yet</h1>'  > /var/www/kids/index.html
[ -e /var/www/solar/index.html ] || echo '<h1>solar not deployed yet</h1>' > /var/www/solar/index.html
sudo chcon -R -t httpd_sys_content_t /var/www/kids /var/www/solar
sudo setsebool -P httpd_can_network_connect 1

sed -e "s/KIDS_HOST/$KIDS_HOST/g" -e "s/SOLAR_HOST/$SOLAR_HOST/g" "${INC_SRC:-/tmp/nginx-revakunj.inc}" | sudo tee $INC >/dev/null

# Hook the include into the TLS server block (right after ssl_protocols).
if ! sudo grep -q rp-revakunj-locations $CONF; then
  sudo cp $CONF $CONF.bak.$(date +%s)
  sudo sed -i "/ssl_protocols/a\\    include /etc/nginx/rp-revakunj-locations*.inc;" $CONF
fi
sudo nginx -t
sudo systemctl reload nginx
echo "nginx: /kids -> $KIDS_HOST:5900, /solar -> $SOLAR_HOST:5901"
