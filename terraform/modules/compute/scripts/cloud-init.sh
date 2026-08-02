#!/usr/bin/env bash
# cloud-init bootstrap: install Java 21 and prepare systemd service directory
set -euo pipefail

dnf update -y
dnf install -y java-21-openjdk-headless

mkdir -p /opt/rp-app
useradd -r -s /sbin/nologin rp-app || true
chown rp-app:rp-app /opt/rp-app
