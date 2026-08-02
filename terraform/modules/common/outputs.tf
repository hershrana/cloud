output "availability_domain" {
  description = "First availability domain in the region."
  value       = local.availability_domain
}

output "common_tags" {
  description = "Standard tags applied to all resources."
  value       = local.common_tags
}
