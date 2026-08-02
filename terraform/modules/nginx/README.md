# Module: nginx

Provisions an OCI Ampere A1 Flex instance configured as an Nginx reverse proxy.

## Resources

- `oci_core_instance` — Nginx instance (cloud-init installs and configures Nginx)

## Behaviour

- Proxies all HTTP traffic to the Spring Boot backend on port 8080.
- Exposes a `/health` endpoint for load-balancer health checks.
- TLS termination is handled by Ansible in v0.7.0.

## Outputs

| Name               | Description                          |
|--------------------|--------------------------------------|
| `instance_id`      | OCID of the Nginx instance           |
| `load_balancer_ip` | Public IP (entry point for all traffic)|
