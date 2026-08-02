# Module: compute

Provisions an OCI Ampere A1 Flex instance (Always Free eligible) running Oracle Linux 9.

## Resources

- `oci_core_instance` — ARM-based compute instance
- Cloud-init script installs Java 21 and creates the `rp-app` service user

## Variables

| Name                  | Default                  | Description                         |
|-----------------------|--------------------------|-------------------------------------|
| `instance_shape`      | `VM.Standard.A1.Flex`    | Always Free Ampere shape            |
| `ocpus`               | `2`                      | OCPUs (up to 4 free across A1 pool) |
| `memory_in_gbs`       | `12`                     | RAM (up to 24 GB free across A1 pool)|

## Outputs

| Name          | Description                    |
|---------------|--------------------------------|
| `instance_id` | OCID of the instance           |
| `public_ip`   | Public IP address              |
| `private_ip`  | Private IP address             |
