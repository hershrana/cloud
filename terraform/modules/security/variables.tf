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

variable "vcn_id" {
  description = "OCID of the VCN in which to create NSGs."
  type        = string
}

variable "subnet_ids" {
  description = "Map of subnet name to OCID (unused directly, reserved for security list rules)."
  type        = map(string)
  default     = {}
}
