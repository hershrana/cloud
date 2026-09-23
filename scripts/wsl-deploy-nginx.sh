#!/bin/bash
set -e
cd "/mnt/d/cloud/oci-spring-platform"
export APP_PUBLIC_IP=92.4.94.109
export NGINX_PUBLIC_IP=137.23.57.203
export APP_PRIVATE_IP=10.0.1.85
export SSH_PRIVATE_KEY_PATH=~/.ssh/oci_purvi
export ANSIBLE_HOST_KEY_CHECKING=False
~/.local/bin/ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/nginx.yml
