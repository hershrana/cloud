# Module: security

Manages OCI Network Security Groups (NSGs) and ingress/egress rules.

## NSGs Created

| NSG              | Purpose                              |
|------------------|--------------------------------------|
| `compute`        | Spring Boot instances (SSH + 8080)   |
| `nginx`          | Nginx reverse proxy (HTTP/HTTPS)     |

> MySQL HeatWave traffic (port 3306) is governed by the private subnet's
> security list in the `network` module, not by an NSG.

## Outputs

| Name             | Description                   |
|------------------|-------------------------------|
| `compute_nsg_id` | OCID of the compute NSG       |
| `nginx_nsg_id`   | OCID of the Nginx NSG         |
