output "db_system_id" {
  description = "OCID of the MySQL DB system."
  value       = oci_mysql_mysql_db_system.main.id
}

output "endpoint" {
  description = "MySQL connection endpoint (host:port)."
  value       = "${oci_mysql_mysql_db_system.main.endpoints[0].hostname}:${oci_mysql_mysql_db_system.main.endpoints[0].port}"
  sensitive   = true
}

output "ip_address" {
  description = "Private IP address of the MySQL DB system."
  value       = oci_mysql_mysql_db_system.main.ip_address
  sensitive   = true
}
