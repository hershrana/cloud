variable "tenancy_ocid" {
  description = "OCID of the OCI tenancy."
  type        = string
}

variable "user_ocid" {
  description = "OCID of the OCI user."
  type        = string
}

variable "fingerprint" {
  description = "Fingerprint of the OCI API key."
  type        = string
}

variable "private_key_path" {
  description = "Path to the OCI API private key file."
  type        = string
  sensitive   = true
}

variable "region" {
  description = "OCI region identifier."
  type        = string
  default     = "us-ashburn-1"
}

variable "compartment_id" {
  description = "OCID of the compartment in which to create resources."
  type        = string
}

variable "project_name" {
  description = "Short name used to prefix all resource names."
  type        = string
  default     = "rp-app"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)."
  type        = string
  default     = "prod"
}

variable "ssh_public_key" {
  description = "Public SSH key to provision on compute instances."
  type        = string
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access the platform."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "mysql_admin_username" {
  description = "MySQL HeatWave admin username."
  type        = string
  default     = "admin"
}

variable "mysql_admin_password" {
  description = "MySQL HeatWave admin password."
  type        = string
  sensitive   = true
}

# --- Always Free A1 sizing (combined budget: 4 OCPUs / 24 GB) ---

variable "app_ocpus" {
  description = "OCPUs for the Spring Boot instance."
  type        = number
  default     = 2
}

variable "app_memory_in_gbs" {
  description = "Memory (GB) for the Spring Boot instance."
  type        = number
  default     = 12
}

variable "nginx_ocpus" {
  description = "OCPUs for the Nginx instance."
  type        = number
  default     = 1
}

variable "nginx_memory_in_gbs" {
  description = "Memory (GB) for the Nginx instance."
  type        = number
  default     = 6
}
