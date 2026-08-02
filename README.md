# OCI Spring Platform

Production-grade OCI Always Free platform: Terraform + Ansible + Java 21 + Spring Boot + Nginx + MySQL HeatWave.

## Architecture

```
Internet → Nginx (public subnet, HTTP/HTTPS)
             → Spring Boot (public subnet, port 8080 reachable only from the Nginx NSG)
                  → MySQL HeatWave (private subnet, port 3306 reachable only from the compute NSG)
```

The Spring Boot instance keeps a public IP for direct SSH-based Ansible deploys, but its
application port (8080) is locked down by NSG so only the Nginx instance can reach it. MySQL
HeatWave sits in the private subnet and is never exposed to the internet.

## Prerequisites

- OCI account with Always Free resources available
- Terraform >= 1.6
- Ansible >= 2.15
- OCI CLI configured (`~/.oci/config`)

## Always Free budget

Every resource in this stack is provisioned within the OCI Always Free tier. Terraform
validations and a `check` block enforce these limits, so `plan`/`apply` fails fast if a
value would push you into paid usage.

| Resource            | Always Free limit                     | This stack uses                          |
|---------------------|---------------------------------------|------------------------------------------|
| Ampere A1 compute   | 4 OCPUs / 24 GB RAM total             | App 2 OCPU/12 GB + Nginx 1 OCPU/6 GB      |
| Block storage       | 200 GB total                          | 2 boot volumes × 50 GB = 100 GB           |
| MySQL HeatWave      | `MySQL.Free` shape, 50 GB storage     | `MySQL.Free`, 50 GB, single node (no HA)  |
| Networking gateways | Internet / NAT / Service GW are free  | Internet GW + NAT GW                       |
| Monitoring / ONS    | Free within generous limits           | 2 alarms + 1 notification topic           |
| Load balancing      | Flexible LB 10 Mbps (not used here)   | Nginx on A1 compute instead               |

> Allowed compute shapes are restricted to `VM.Standard.A1.Flex` and
> `VM.Standard.E2.1.Micro`; any other shape is rejected by variable validation.

## Quick Start

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your OCI credentials and settings
terraform init
terraform plan
terraform apply
```

After `apply`, use the output IPs in the Ansible inventory:

```bash
export APP_PUBLIC_IP=$(terraform output -raw compute_public_ip)
export NGINX_PUBLIC_IP=$(terraform output -raw load_balancer_ip)
export APP_PRIVATE_IP=$(terraform output -raw compute_private_ip)  # add to outputs if needed
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/site.yml
```

## Project Structure

```
terraform/
  main.tf                     Root module wiring all modules together
  variables.tf                All input variables
  outputs.tf                  Key outputs (IPs, endpoints)
  versions.tf                 Provider version constraints
  terraform.tfvars.example    Template for secrets (never commit tfvars)
  modules/
    common/                   Shared data sources and tags
    network/                  VCN, subnets, gateways, route tables
    security/                 Network Security Groups and rules
    compute/                  Spring Boot Ampere A1 instance
    mysql/                    MySQL HeatWave Free DB system
    nginx/                    Nginx reverse-proxy Ampere A1 instance
    monitoring/               OCI Monitoring alarms and ONS alerts
ansible/
  inventory/hosts.yml         Dynamic host inventory (reads from env vars)
  playbooks/
    site.yml                  Full platform playbook
    nginx.yml                 Nginx configuration
    spring_boot.yml           Spring Boot JAR deployment + systemd
  templates/
    nginx-vhost.conf.j2       Nginx virtual-host template
    rp-app.env.j2             Spring Boot environment file
    rp-app.service.j2         systemd unit template
.github/workflows/
  terraform.yml               Validate → Plan (PR) → Apply (main)
  ansible.yml                 Deploy on push or manual trigger
```

## Roadmap

| Version | Milestone             |
|---------|-----------------------|
| v0.1.0  | Foundation            |
| v0.2.0  | Networking            |
| v0.3.0  | Compute               |
| v0.4.0  | MySQL HeatWave        |
| v0.5.0  | Ansible               |
| v0.6.0  | Spring Boot           |
| v0.7.0  | Nginx                 |
| v0.8.0  | GitHub Actions        |
| v0.9.0  | Monitoring            |
| v1.0.0  | Production            |

## Required GitHub Secrets

| Secret                 | Description                                |
|------------------------|--------------------------------------------|
| `OCI_TENANCY_OCID`     | OCI tenancy OCID                           |
| `OCI_USER_OCID`        | OCI user OCID                              |
| `OCI_FINGERPRINT`      | OCI API key fingerprint                    |
| `OCI_PRIVATE_KEY`      | OCI API private key (PEM, no passphrase)   |
| `OCI_REGION`           | OCI region identifier                      |
| `OCI_COMPARTMENT_ID`   | Target compartment OCID                    |
| `SSH_PUBLIC_KEY`       | SSH public key for compute instances       |
| `SSH_PRIVATE_KEY`      | SSH private key for Ansible                |
| `MYSQL_ADMIN_PASSWORD` | MySQL HeatWave admin password              |
| `APP_PUBLIC_IP`        | Compute instance public IP (post-apply)    |
| `NGINX_PUBLIC_IP`      | Nginx instance public IP (post-apply)      |
| `APP_PRIVATE_IP`       | Compute instance private IP (post-apply)   |
| `DB_HOST`              | MySQL HeatWave private hostname            |
| `DB_NAME`              | Database name                              |
| `DB_USERNAME`          | Database username                          |
| `DB_PASSWORD`          | Database password                          |
