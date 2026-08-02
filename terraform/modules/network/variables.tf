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

variable "vcn_cidr" {
  description = "CIDR block for the VCN."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet."
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet (compute and MySQL)."
  type        = string
  default     = "10.0.2.0/24"
}
