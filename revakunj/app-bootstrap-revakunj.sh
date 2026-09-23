#!/usr/bin/env bash
# Run ON EACH BOX that hosts a revakunj backend (idempotent, holds no secrets).
# Usage: APPS="kids learning" bash app-bootstrap-revakunj.sh    (or APPS="solar")
# List EVERY app on the box: /etc/sudoers.d/revakunj is rewritten from APPS.
#
# DB credentials and the JWT secret are NOT set here: the GitHub Actions deploy
# job writes /opt/revakunj/<app>/env from repo secrets on every deploy.
set -euo pipefail

declare -A PORT=([kids]=5900 [solar]=5901 [learning]=5902) \
           JAR=([kids]=kids-money-game [solar]=solar-ev-tracker [learning]=learning)
APPS="${APPS:?set APPS to the apps on this box, e.g. \"kids learning\" or \"solar learning\"}"

# Spring Boot 3.2 / pom java.version=17
# Full-repo dnf gets OOM-killed on the 0.5 GB micro box; skip if present and
# otherwise load only the two repos Java needs.
rpm -q java-17-openjdk-headless >/dev/null || sudo dnf install -y \
  --disablerepo='*' --enablerepo=ol9_baseos_latest,ol9_appstream java-17-openjdk-headless >/dev/null
sudo useradd -r -s /sbin/nologin rp-app 2>/dev/null || true
sudo mkdir -p /opt/revakunj

for name in $APPS; do
  port=${PORT[$name]}; jar=${JAR[$name]}
  # opc (CI deploy user) owns the dir and writes jar + env; rp-app only reads.
  sudo mkdir -p /opt/revakunj/$name
  sudo chown opc:rp-app /opt/revakunj/$name
  sudo chmod 2750 /opt/revakunj/$name   # setgid: uploaded jars inherit group rp-app
  sudo tee /etc/systemd/system/revakunj-$name.service >/dev/null <<UNIT
[Unit]
Description=revakunj $jar
After=network-online.target
Wants=network-online.target
ConditionPathExists=/opt/revakunj/$name/app.jar

[Service]
User=rp-app
EnvironmentFile=/opt/revakunj/$name/env
ExecStart=/usr/bin/java -Xmx192m -XX:MaxMetaspaceSize=128m -XX:+UseSerialGC -Xss512k -jar /opt/revakunj/$name/app.jar
Restart=on-failure
RestartSec=15
SuccessExitStatus=143

[Install]
WantedBy=multi-user.target
UNIT
  sudo firewall-cmd --permanent --add-rich-rule="rule family=\"ipv4\" source address=\"10.0.0.0/16\" port port=\"$port\" protocol=\"tcp\" accept" >/dev/null || true
done

# Passwordless restart of these units for the CI deploy user, nothing else
sudo tee /etc/sudoers.d/revakunj >/dev/null <<SUDO
opc ALL=(root) NOPASSWD: $(for n in $APPS; do printf "/usr/bin/systemctl restart revakunj-%s, " $n; done | sed "s/, $//")
SUDO
sudo chmod 440 /etc/sudoers.d/revakunj
sudo visudo -cf /etc/sudoers.d/revakunj

sudo systemctl daemon-reload
for name in $APPS; do sudo systemctl enable revakunj-$name; done
sudo firewall-cmd --reload >/dev/null || true
echo "Done ($APPS). Services start on first CI deploy."
