locals {
  cluster_name = var.use_custom_name ? var.cluster_name : "${var.cluster_name}-${random_pet.name.id}"

  vcn_compartment = var.vcn_compartment_ocid != "" ? var.vcn_compartment_ocid : var.compartment_ocid

  vcn_id    = var.use_existing_vcn ? var.existing_vcn_id : oci_core_vcn.aeron_vcn[0].id
  subnet_id = var.use_existing_vcn ? var.existing_subnet_id : oci_core_subnet.public_subnet[0].id

  is_primary_flex_shape  = length(regexall(".*Flex$", var.primary_shape)) > 0
  is_failover_flex_shape = length(regexall(".*Flex$", var.failover_shape)) > 0

  primary_host   = var.private_deployment ? oci_core_instance.primary.private_ip : oci_core_instance.primary.public_ip
  failover_host  = var.enable_failover_node ? (var.private_deployment ? oci_core_instance.failover[0].private_ip : oci_core_instance.failover[0].public_ip) : ""

  compute_image = var.use_marketplace_image ? data.oci_core_images.oracle_linux.images[0].id : var.image_ocid

  platform_config_type = contains(["BM.Standard.E4.128", "BM.Standard.E5.192", "BM.DenseIO.E4.128", "BM.DenseIO.E5.128"], var.primary_shape) ? "AMD_MILAN_BM" : contains(["BM.Standard.E3.128", "BM.DenseIO.E3.128"], var.primary_shape) ? "AMD_ROME_BM" : null
}

resource "random_pet" "name" {
  length = 2
}

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
