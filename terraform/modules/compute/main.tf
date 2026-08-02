data "oci_core_images" "oracle_linux" {
  compartment_id           = var.context.compartment_id
  operating_system         = "Oracle Linux"
  operating_system_version = "9"
  shape                    = var.instance_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

resource "oci_core_instance" "app" {
  compartment_id      = var.context.compartment_id
  availability_domain = var.availability_domain
  display_name        = "${var.context.project_name}-app"
  shape               = var.instance_shape

  shape_config {
    ocpus         = var.ocpus
    memory_in_gbs = var.memory_in_gbs
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.oracle_linux.images[0].id
    boot_volume_size_in_gbs = var.boot_volume_size_in_gbs
  }

  create_vnic_details {
    subnet_id        = var.subnet_id
    assign_public_ip = true
    nsg_ids          = var.nsg_ids
    display_name     = "${var.context.project_name}-app-vnic"
  }

  metadata = {
    ssh_authorized_keys = var.context.ssh_public_key
    user_data           = base64encode(file("${path.module}/scripts/cloud-init.sh"))
  }

  freeform_tags = {
    Project     = var.context.project_name
    Environment = var.context.environment
    ManagedBy   = "Terraform"
  }
}
