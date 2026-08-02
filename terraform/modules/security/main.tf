resource "oci_core_network_security_group" "compute" {
  compartment_id = var.context.compartment_id
  vcn_id         = var.vcn_id
  display_name   = "${var.context.project_name}-compute-nsg"
}

resource "oci_core_network_security_group" "nginx" {
  compartment_id = var.context.compartment_id
  vcn_id         = var.vcn_id
  display_name   = "${var.context.project_name}-nginx-nsg"
}

# Allow SSH to compute from specified CIDRs
resource "oci_core_network_security_group_security_rule" "compute_ssh_ingress" {
  for_each                  = toset(var.context.allowed_cidr_blocks)
  network_security_group_id = oci_core_network_security_group.compute.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = each.value
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 22
      max = 22
    }
  }
}

# Allow Spring Boot backend ports (5857 jira, 5855 todo) from Nginx NSG
resource "oci_core_network_security_group_security_rule" "compute_app_ingress" {
  network_security_group_id = oci_core_network_security_group.compute.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = oci_core_network_security_group.nginx.id
  source_type               = "NETWORK_SECURITY_GROUP"

  tcp_options {
    destination_port_range {
      min = 5855
      max = 5857
    }
  }
}

# Allow all egress from compute
resource "oci_core_network_security_group_security_rule" "compute_egress" {
  network_security_group_id = oci_core_network_security_group.compute.id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
}

# Allow HTTP/HTTPS to Nginx from the internet
resource "oci_core_network_security_group_security_rule" "nginx_http_ingress" {
  for_each                  = toset(["80", "443"])
  network_security_group_id = oci_core_network_security_group.nginx.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = tonumber(each.value)
      max = tonumber(each.value)
    }
  }
}

# Allow all egress from Nginx
resource "oci_core_network_security_group_security_rule" "nginx_egress" {
  network_security_group_id = oci_core_network_security_group.nginx.id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
}
