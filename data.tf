data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

data "oci_core_services" "all_services" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

data "oci_core_images" "oracle_linux" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Oracle Linux"
  operating_system_version = "8"
  shape                    = var.primary_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"

  filter {
    name   = "display_name"
    values = ["^Oracle-Linux-8\\.[0-9]+-[0-9]{4}\\.[0-9]{2}\\.[0-9]{2}-[0-9]+$"]
    regex  = true
  }
}

data "oci_core_vcns" "existing_vcns" {
  count          = var.use_existing_vcn ? 0 : 1
  compartment_id = local.vcn_compartment
  state          = "AVAILABLE"
}
