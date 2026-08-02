#!/usr/bin/env bash
# cloud-init bootstrap: swap + Java 21 for the Spring Boot app host.
set -euo pipefail

# Create swap first so the 1 GB micro instance doesn't OOM during installs / running JVMs.
if [ ! -f /swapfile ]; then
  fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# Install only what we need (a full 'dnf update' is too heavy for 1 GB).
dnf install -y java-21-openjdk-headless

mkdir -p /opt/rp-app
useradd -r -s /sbin/nologin rp-app || true
chown rp-app:rp-app /opt/rp-app
