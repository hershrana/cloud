resource "oci_mysql_mysql_db_system" "main" {
  compartment_id      = var.context.compartment_id
  availability_domain = var.availability_domain
  display_name        = "${var.context.project_name}-mysql"
  description         = "MySQL HeatWave Free instance for ${var.context.project_name}"

  shape_name    = var.shape_name
  mysql_version = var.mysql_version

  subnet_id      = var.subnet_id
  hostname_label = replace(var.context.project_name, "-", "")

  admin_username = var.admin_username
  admin_password = var.admin_password

  data_storage_size_in_gb = var.data_storage_size_in_gb

  is_highly_available = false

  freeform_tags = {
    Project     = var.context.project_name
    Environment = var.context.environment
    ManagedBy   = "Terraform"
  }
}
