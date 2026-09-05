data "oci_core_images" "oracle_linux_nginx" {
  compartment_id           = var.context.compartment_id
  operating_system         = "Oracle Linux"
  operating_system_version = "9"
  shape                    = var.instance_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

resource "oci_core_instance" "nginx" {
  compartment_id      = var.context.compartment_id
  availability_domain = var.availability_domain
  display_name        = "${var.context.project_name}-nginx"
  shape               = var.instance_shape

  # shape_config is only valid for flexible shapes; fixed shapes (E2.1.Micro) reject it.
  dynamic "shape_config" {
    for_each = can(regex("Flex$", var.instance_shape)) ? [1] : []
    content {
      ocpus         = var.ocpus
      memory_in_gbs = var.memory_in_gbs
    }
  }

  source_details {
    source_type             = "image"
    source_id               = var.image_id != null ? var.image_id : data.oci_core_images.oracle_linux_nginx.images[0].id
    boot_volume_size_in_gbs = var.boot_volume_size_in_gbs
  }

  create_vnic_details {
    subnet_id        = var.subnet_id
    assign_public_ip = true
    nsg_ids          = var.nsg_ids
    display_name     = "${var.context.project_name}-nginx-vnic"
  }

  metadata = {
    ssh_authorized_keys = var.context.ssh_public_key
    user_data = base64encode(templatefile("${path.module}/templates/nginx-cloud-init.sh.tpl", {
      backend_ip   = var.backend_ip
      backend_port = var.backend_port
    }))
  }

  freeform_tags = {
    Project     = var.context.project_name
    Environment = var.context.environment
    ManagedBy   = "Terraform"
  }
}
