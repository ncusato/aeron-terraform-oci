# Primary Aeron Node
resource "oci_core_instance" "primary" {
  availability_domain = var.primary_ad
  compartment_id      = var.compartment_ocid
  shape               = var.primary_shape
  display_name        = "${local.cluster_name}-primary"

  dynamic "shape_config" {
    for_each = local.is_primary_flex_shape ? [1] : []
    content {
      ocpus         = var.primary_ocpus
      memory_in_gbs = var.primary_memory_gb
    }
  }

  dynamic "platform_config" {
    for_each = local.platform_config_type != null || !var.hyperthreading ? [1] : []
    content {
      type                                    = local.platform_config_type != null ? local.platform_config_type : "AMD_VM"
      is_symmetric_multi_threading_enabled    = var.hyperthreading
      are_virtual_instructions_enabled        = false
      is_access_control_service_enabled       = false
      is_input_output_memory_management_unit_enabled = false
    }
  }

  source_details {
    source_type             = "image"
    source_id               = local.compute_image
    boot_volume_size_in_gbs = var.primary_boot_volume_size_gb
    boot_volume_vpus_per_gb = 20
  }

  create_vnic_details {
    subnet_id        = local.subnet_id
    assign_public_ip = !var.private_deployment
    hostname_label   = "primary"
  }

  metadata = {
    ssh_authorized_keys = "${var.ssh_public_key}\n${tls_private_key.ssh.public_key_openssh}"
    user_data           = base64encode(templatefile("${path.module}/scripts/cloud-init.yaml", {
      ssh_username     = var.ssh_username
      hyperthreading   = var.hyperthreading
      install_aeron    = var.install_aeron
      aeron_version    = var.aeron_version
      java_version     = var.java_version
    }))
  }

  agent_config {
    is_management_disabled = false
    is_monitoring_disabled = false
    plugins_config {
      desired_state = "ENABLED"
      name          = "Compute Instance Monitoring"
    }
  }

  freeform_tags = {
    cluster_name = local.cluster_name
    role         = "primary"
    aeron        = "true"
  }

  lifecycle {
    ignore_changes = [
      source_details[0].source_id,
    ]
  }
}

# Failover Aeron Node (Optional, in different AD)
resource "oci_core_instance" "failover" {
  count               = var.enable_failover_node ? 1 : 0
  availability_domain = var.failover_ad
  compartment_id      = var.compartment_ocid
  shape               = var.failover_shape
  display_name        = "${local.cluster_name}-failover"

  dynamic "shape_config" {
    for_each = local.is_failover_flex_shape ? [1] : []
    content {
      ocpus         = var.failover_ocpus
      memory_in_gbs = var.failover_memory_gb
    }
  }

  dynamic "platform_config" {
    for_each = local.platform_config_type != null || !var.hyperthreading ? [1] : []
    content {
      type                                    = local.platform_config_type != null ? local.platform_config_type : "AMD_VM"
      is_symmetric_multi_threading_enabled    = var.hyperthreading
      are_virtual_instructions_enabled        = false
      is_access_control_service_enabled       = false
      is_input_output_memory_management_unit_enabled = false
    }
  }

  source_details {
    source_type             = "image"
    source_id               = local.compute_image
    boot_volume_size_in_gbs = var.failover_boot_volume_size_gb
    boot_volume_vpus_per_gb = 20
  }

  create_vnic_details {
    subnet_id        = local.subnet_id
    assign_public_ip = !var.private_deployment
    hostname_label   = "failover"
  }

  metadata = {
    ssh_authorized_keys = "${var.ssh_public_key}\n${tls_private_key.ssh.public_key_openssh}"
    user_data           = base64encode(templatefile("${path.module}/scripts/cloud-init.yaml", {
      ssh_username     = var.ssh_username
      hyperthreading   = var.hyperthreading
      install_aeron    = var.install_aeron
      aeron_version    = var.aeron_version
      java_version     = var.java_version
    }))
  }

  agent_config {
    is_management_disabled = false
    is_monitoring_disabled = false
    plugins_config {
      desired_state = "ENABLED"
      name          = "Compute Instance Monitoring"
    }
  }

  freeform_tags = {
    cluster_name = local.cluster_name
    role         = "failover"
    aeron        = "true"
  }

  lifecycle {
    ignore_changes = [
      source_details[0].source_id,
    ]
  }
}

# Provisioner for Primary Node
resource "null_resource" "primary_provisioner" {
  depends_on = [oci_core_instance.primary]

  triggers = {
    instance_id = oci_core_instance.primary.id
  }

  connection {
    type        = "ssh"
    host        = local.primary_host
    user        = var.ssh_username
    private_key = tls_private_key.ssh.private_key_pem
    timeout     = "10m"
  }

  provisioner "remote-exec" {
    inline = [
      "#!/bin/bash",
      "set -e",
      "echo 'Waiting for cloud-init to complete...'",
      "cloud-init status --wait || true",
      "echo 'Primary node provisioning complete'",
    ]
  }

  provisioner "file" {
    source      = "${path.module}/playbooks/"
    destination = "/tmp/playbooks"
  }

  provisioner "remote-exec" {
    inline = [
      "#!/bin/bash",
      "set -e",
      "sudo mkdir -p /opt/aeron",
      "sudo mv /tmp/playbooks /opt/aeron/",
      "sudo chown -R ${var.ssh_username}:${var.ssh_username} /opt/aeron",
      var.install_aeron ? "cd /opt/aeron/playbooks && ansible-playbook -i 'localhost,' -c local site.yml -e 'hyperthreading=${var.hyperthreading} aeron_version=${var.aeron_version} java_version=${var.java_version}'" : "echo 'Skipping Aeron installation'",
    ]
  }
}

# Provisioner for Failover Node
resource "null_resource" "failover_provisioner" {
  count      = var.enable_failover_node ? 1 : 0
  depends_on = [oci_core_instance.failover]

  triggers = {
    instance_id = oci_core_instance.failover[0].id
  }

  connection {
    type        = "ssh"
    host        = local.failover_host
    user        = var.ssh_username
    private_key = tls_private_key.ssh.private_key_pem
    timeout     = "10m"
  }

  provisioner "remote-exec" {
    inline = [
      "#!/bin/bash",
      "set -e",
      "echo 'Waiting for cloud-init to complete...'",
      "cloud-init status --wait || true",
      "echo 'Failover node provisioning complete'",
    ]
  }

  provisioner "file" {
    source      = "${path.module}/playbooks/"
    destination = "/tmp/playbooks"
  }

  provisioner "remote-exec" {
    inline = [
      "#!/bin/bash",
      "set -e",
      "sudo mkdir -p /opt/aeron",
      "sudo mv /tmp/playbooks /opt/aeron/",
      "sudo chown -R ${var.ssh_username}:${var.ssh_username} /opt/aeron",
      var.install_aeron ? "cd /opt/aeron/playbooks && ansible-playbook -i 'localhost,' -c local site.yml -e 'hyperthreading=${var.hyperthreading} aeron_version=${var.aeron_version} java_version=${var.java_version}'" : "echo 'Skipping Aeron installation'",
    ]
  }
}
