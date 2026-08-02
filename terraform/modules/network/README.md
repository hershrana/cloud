# Module: network

Creates the OCI VCN, Internet Gateway, NAT Gateway, route tables, and subnets.

## Resources

- `oci_core_vcn` — Virtual Cloud Network
- `oci_core_internet_gateway` — Internet Gateway for public subnet
- `oci_core_nat_gateway` — NAT Gateway for private subnet egress
- `oci_core_route_table` (public / private)
- `oci_core_subnet` (public / private)

## Outputs

| Name               | Description              |
|--------------------|--------------------------|
| `vcn_id`           | OCID of the VCN          |
| `public_subnet_id` | OCID of the public subnet|
| `private_subnet_id`| OCID of the private subnet|
| `subnet_ids`       | Map of subnet name → OCID|
