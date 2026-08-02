output "compute_nsg_id" {
  description = "OCID of the compute Network Security Group."
  value       = oci_core_network_security_group.compute.id
}

output "nginx_nsg_id" {
  description = "OCID of the Nginx Network Security Group."
  value       = oci_core_network_security_group.nginx.id
}
