output "instance_id" {
  description = "OCID of the Nginx instance."
  value       = oci_core_instance.nginx.id
}

output "load_balancer_ip" {
  description = "Public IP of the Nginx reverse-proxy instance."
  value       = oci_core_instance.nginx.public_ip
}
