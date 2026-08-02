#!/usr/bin/env bash
# App-box bootstrap: dirs, env files, systemd units for both backends, MySQL databases.
set -euo pipefail

MYSQL_HOST="rpapp.private.rpapp.oraclevcn.com"
MYSQL_PORT="3306"
MYSQL_ADMIN="admin"
# Password is exported by the caller as MYSQL_PWD (never echoed / never in argv)

echo "== Installing MySQL client =="
sudo dnf install -y mysql >/dev/null 2>&1 || sudo dnf install -y mysql-community-client >/dev/null 2>&1 || true

echo "== Waiting for Java =="
for i in $(seq 1 60); do
  if command -v java >/dev/null 2>&1; then break; fi
  sleep 10
done
java -version || { echo "Java not installed yet"; }

echo "== Ensuring service user exists =="
sudo useradd -r -s /sbin/nologin rp-app 2>/dev/null || true

echo "== Creating app directories =="
sudo mkdir -p /opt/jira /opt/todo
sudo chown rp-app:rp-app /opt/jira /opt/todo

echo "== Writing environment files =="
sudo tee /opt/jira/env >/dev/null <<EOF
DB_URL=jdbc:mysql://${MYSQL_HOST}:${MYSQL_PORT}/jira
DB_USERNAME=${MYSQL_ADMIN}
DB_PASSWORD=${MYSQL_PWD}
JWT_SECRET=${JWT_SECRET:-change-me-please-a-very-long-secret-key-0123456789}
JAVA_TOOL_OPTIONS=-Xmx192m -XX:MaxMetaspaceSize=128m
EOF

sudo tee /opt/todo/env >/dev/null <<EOF
DB_R2DBC_URL=r2dbc:mysql://${MYSQL_HOST}:${MYSQL_PORT}/todo
DB_JDBC_URL=jdbc:mysql://${MYSQL_HOST}:${MYSQL_PORT}/todo
DB_USERNAME=${MYSQL_ADMIN}
DB_PASSWORD=${MYSQL_PWD}
JAVA_TOOL_OPTIONS=-Xmx192m -XX:MaxMetaspaceSize=128m
EOF

sudo chmod 640 /opt/jira/env /opt/todo/env
sudo chown rp-app:rp-app /opt/jira/env /opt/todo/env

echo "== Writing systemd units =="
sudo tee /etc/systemd/system/jira-backend.service >/dev/null <<'EOF'
[Unit]
Description=Jira Backend (Spring Boot)
After=network-online.target
Wants=network-online.target

[Service]
User=rp-app
EnvironmentFile=/opt/jira/env
ExecStart=/usr/bin/java -jar /opt/jira/jira.jar
Restart=on-failure
RestartSec=15
SuccessExitStatus=143

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/todo-backend.service >/dev/null <<'EOF'
[Unit]
Description=Todo Backend (Spring Boot)
After=network-online.target
Wants=network-online.target

[Service]
User=rp-app
EnvironmentFile=/opt/todo/env
ExecStart=/usr/bin/java -jar /opt/todo/todo.jar
Restart=on-failure
RestartSec=15
SuccessExitStatus=143

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable jira-backend todo-backend >/dev/null 2>&1 || true

echo "== Opening firewall for backend ports (VCN subnet only) =="
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.0.0.0/16" port port="5855-5857" protocol="tcp" accept' 2>/dev/null || true
sudo firewall-cmd --reload 2>/dev/null || true
if command -v mysql >/dev/null 2>&1; then
  mysql -h "${MYSQL_HOST}" -P "${MYSQL_PORT}" -u "${MYSQL_ADMIN}" \
    -e "CREATE DATABASE IF NOT EXISTS jira CHARACTER SET utf8mb4; CREATE DATABASE IF NOT EXISTS todo CHARACTER SET utf8mb4; SHOW DATABASES;" \
    && echo "Databases ready." \
    || echo "DB creation failed - check MySQL connectivity/credentials."
else
  echo "mysql client unavailable - create databases manually."
fi

echo "== Done =="
