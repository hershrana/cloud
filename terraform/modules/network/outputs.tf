output "vcn_id" {
  description = "OCID of the VCN."
  value       = oci_core_vcn.main.id
}

output "public_subnet_id" {
  description = "OCID of the public subnet."
  value       = oci_core_subnet.public.id
}

output "private_subnet_id" {
  description = "OCID of the private subnet."
  value       = oci_core_subnet.private.id
}

output "subnet_ids" {
  description = "Map of subnet name to OCID."
  value = {
    public  = oci_core_subnet.public.id
    private = oci_core_subnet.private.id
  }
}
