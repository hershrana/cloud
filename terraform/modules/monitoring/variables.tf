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

variable "compartment_id" {
  description = "OCID of the compartment to create monitoring resources in."
  type        = string
}

variable "alert_email" {
  description = "Email address for alarm notifications. Leave empty to skip subscription."
  type        = string
  default     = ""
}
