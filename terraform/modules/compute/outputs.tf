output "instance_id" {
  description = "OCID of the compute instance."
  value       = oci_core_instance.app.id
}

output "public_ip" {
  description = "Public IP address of the instance."
  value       = oci_core_instance.app.public_ip
}

output "private_ip" {
  description = "Private IP address of the instance."
  value       = oci_core_instance.app.private_ip
}
