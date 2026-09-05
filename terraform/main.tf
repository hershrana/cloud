provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}

locals {
  context = {
    tenancy_ocid        = var.tenancy_ocid
    compartment_id      = var.compartment_id
    region              = var.region
    project_name        = var.project_name
    environment         = var.environment
    ssh_public_key      = var.ssh_public_key
    allowed_cidr_blocks = var.allowed_cidr_blocks
  }
}

# Enforce the combined OCI Always Free Ampere A1 budget (4 OCPUs / 24 GB total).
check "always_free_a1_budget" {
  assert {
    condition     = (var.app_ocpus + var.nginx_ocpus) <= 4
    error_message = "Combined A1 OCPUs (app + nginx) must not exceed 4 (Always Free budget)."
  }

  assert {
    condition     = (var.app_memory_in_gbs + var.nginx_memory_in_gbs) <= 24
    error_message = "Combined A1 memory (app + nginx) must not exceed 24 GB (Always Free budget)."
  }
}

module "common" {
  source  = "./modules/common"
  context = local.context
}

module "network" {
  source  = "./modules/network"
  context = local.context
}

module "security" {
  source     = "./modules/security"
  context    = local.context
  vcn_id     = module.network.vcn_id
  subnet_ids = module.network.subnet_ids
}

module "compute" {
  source              = "./modules/compute"
  context             = local.context
  subnet_id           = module.network.public_subnet_id
  nsg_ids             = [module.security.compute_nsg_id]
  availability_domain = module.common.availability_domain
  instance_shape      = var.app_instance_shape
  ocpus               = var.app_ocpus
  memory_in_gbs       = var.app_memory_in_gbs
  image_id            = var.app_image_id
}

module "mysql" {
  source              = "./modules/mysql"
  context             = local.context
  subnet_id           = module.network.private_subnet_id
  availability_domain = module.common.availability_domain
  admin_username      = var.mysql_admin_username
  admin_password      = var.mysql_admin_password
}

module "nginx" {
  source              = "./modules/nginx"
  context             = local.context
  subnet_id           = module.network.public_subnet_id
  nsg_ids             = [module.security.nginx_nsg_id]
  availability_domain = module.common.availability_domain
  instance_shape      = var.nginx_instance_shape
  backend_ip          = module.compute.private_ip
  ocpus               = var.nginx_ocpus
  memory_in_gbs       = var.nginx_memory_in_gbs
  image_id            = var.nginx_image_id
}

module "monitoring" {
  source         = "./modules/monitoring"
  context        = local.context
  compartment_id = var.compartment_id
}
