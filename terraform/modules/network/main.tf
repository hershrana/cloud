resource "oci_core_vcn" "main" {
  compartment_id = var.context.compartment_id
  display_name   = "${var.context.project_name}-vcn"
  cidr_blocks    = [var.vcn_cidr]
  dns_label      = replace(var.context.project_name, "-", "")

  freeform_tags = {
    Project     = var.context.project_name
    Environment = var.context.environment
    ManagedBy   = "Terraform"
  }
}

resource "oci_core_internet_gateway" "igw" {
  compartment_id = var.context.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.context.project_name}-igw"
  enabled        = true
}

resource "oci_core_route_table" "public" {
  compartment_id = var.context.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.context.project_name}-public-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.igw.id
  }
}

# Private subnet has no internet egress; MySQL HeatWave needs none.
resource "oci_core_route_table" "private" {
  compartment_id = var.context.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.context.project_name}-private-rt"
}

resource "oci_core_subnet" "public" {
  compartment_id    = var.context.compartment_id
  vcn_id            = oci_core_vcn.main.id
  display_name      = "${var.context.project_name}-public-subnet"
  cidr_block        = var.public_subnet_cidr
  dns_label         = "public"
  route_table_id    = oci_core_route_table.public.id
  security_list_ids = [oci_core_vcn.main.default_security_list_id]
}

resource "oci_core_security_list" "private" {
  compartment_id = var.context.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.context.project_name}-private-sl"

  egress_security_rules {
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    protocol         = "all"
  }

  # MySQL access from the public subnet (Spring Boot instance)
  ingress_security_rules {
    source      = var.public_subnet_cidr
    source_type = "CIDR_BLOCK"
    protocol    = "6"

    tcp_options {
      min = 3306
      max = 3306
    }
  }

  # MySQL X protocol from the public subnet
  ingress_security_rules {
    source      = var.public_subnet_cidr
    source_type = "CIDR_BLOCK"
    protocol    = "6"

    tcp_options {
      min = 33060
      max = 33060
    }
  }
}

resource "oci_core_subnet" "private" {
  compartment_id             = var.context.compartment_id
  vcn_id                     = oci_core_vcn.main.id
  display_name               = "${var.context.project_name}-private-subnet"
  cidr_block                 = var.private_subnet_cidr
  dns_label                  = "private"
  route_table_id             = oci_core_route_table.private.id
  prohibit_public_ip_on_vnic = true
  security_list_ids          = [oci_core_security_list.private.id]
}
