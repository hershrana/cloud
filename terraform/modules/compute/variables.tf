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
  description = "OCID of the subnet in which to place the instance."
  type        = string
}

variable "nsg_ids" {
  description = "List of NSG OCIDs to attach to the instance VNIC."
  type        = list(string)
  default     = []
}

variable "availability_domain" {
  description = "Availability domain for the instance."
  type        = string
}

variable "instance_shape" {
  description = "OCI shape for the compute instance (Always Free eligible only)."
  type        = string
  default     = "VM.Standard.A1.Flex"

  validation {
    condition     = contains(["VM.Standard.A1.Flex", "VM.Standard.E2.1.Micro"], var.instance_shape)
    error_message = "Only Always Free shapes are allowed: VM.Standard.A1.Flex or VM.Standard.E2.1.Micro."
  }
}

variable "ocpus" {
  description = "Number of OCPUs (Always Free A1 budget: 4 OCPUs total across all A1 instances)."
  type        = number
  default     = 2

  validation {
    condition     = var.ocpus >= 1 && var.ocpus <= 4
    error_message = "OCPUs must be between 1 and 4 to stay within the Always Free A1 budget."
  }
}

variable "memory_in_gbs" {
  description = "Memory in GBs (Always Free A1 budget: 24 GB total across all A1 instances)."
  type        = number
  default     = 12

  validation {
    condition     = var.memory_in_gbs >= 1 && var.memory_in_gbs <= 24
    error_message = "Memory must be between 1 and 24 GB to stay within the Always Free A1 budget."
  }
}

variable "boot_volume_size_in_gbs" {
  description = "Boot volume size in GB (Always Free: 200 GB total block storage across all instances)."
  type        = number
  default     = 50

  validation {
    condition     = var.boot_volume_size_in_gbs >= 50 && var.boot_volume_size_in_gbs <= 100
    error_message = "Boot volume must be between 50 and 100 GB to stay within the Always Free storage budget."
  }
}
