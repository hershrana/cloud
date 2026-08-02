variable "context" {
  description = "Shared context object propagated across all modules."
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
