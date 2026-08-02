output "compute_public_ip" {
  description = "Public IP address of the primary compute instance."
  value       = module.compute.public_ip
}

output "compute_private_ip" {
  description = "Private IP address of the primary compute instance."
  value       = module.compute.private_ip
}

output "mysql_endpoint" {
  description = "MySQL HeatWave connection endpoint."
  value       = module.mysql.endpoint
  sensitive   = true
}

output "vcn_id" {
  description = "OCID of the VCN."
  value       = module.network.vcn_id
}

output "load_balancer_ip" {
  description = "Public IP of the load balancer (Nginx entry point)."
  value       = module.nginx.load_balancer_ip
}
