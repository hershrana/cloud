variable "context" {
  description = "Shared context object."
  type = object({
    tenancy_ocid        = string
    compartment_id      = string
    region              = string
    project_name        = string
    environment         = string
    ssh_public_key      = string
    allowed_cidr_blocks = list(string)
  })
}

variable "subnet_id" {
  description = "OCID of the private subnet for the MySQL DB system."
  type        = string
}

variable "availability_domain" {
  description = "Availability domain for the MySQL DB system."
  type        = string
}

variable "admin_username" {
  description = "MySQL administrator username."
  type        = string
}

variable "admin_password" {
  description = "MySQL administrator password."
  type        = string
  sensitive   = true
}

variable "shape_name" {
  description = "MySQL HeatWave Free shape."
  type        = string
  default     = "MySQL.Free"

  validation {
    condition     = var.shape_name == "MySQL.Free"
    error_message = "Only the Always Free MySQL shape (MySQL.Free) is allowed."
  }
}

variable "mysql_version" {
  description = "MySQL version to deploy."
  type        = string
  default     = "8.4.3"
}

variable "data_storage_size_in_gb" {
  description = "Data storage allocated in GB (Always Free: 50 GB)."
  type        = number
  default     = 50

  validation {
    condition     = var.data_storage_size_in_gb <= 50
    error_message = "Always Free MySQL is limited to 50 GB of data storage."
  }
}
