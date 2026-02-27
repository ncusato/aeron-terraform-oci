# =============================================================================
# Controller Node (Public Subnet - Orchestrator)
# =============================================================================
resource "oci_core_instance" "controller" {
  availability_domain = var.controller_ad
  compartment_id      = var.compartment_ocid
  shape               = var.controller_shape
  display_name        = "${local.cluster_name}-controller"

  dynamic "shape_config" {
    for_each = local.is_controller_flex_shape ? [1] : []
    content {
      ocpus         = var.controller_ocpus
      memory_in_gbs = var.controller_memory_gb
    }
  }

  source_details {
    source_type             = "image"
    source_id               = local.compute_image
    boot_volume_size_in_gbs = var.controller_boot_volume_size_gb
    boot_volume_vpus_per_gb = 10
  }

  create_vnic_details {
    subnet_id        = local.public_subnet_id
    assign_public_ip = !var.private_deployment
    hostname_label   = "controller"
  }

  metadata = {
    ssh_authorized_keys = "${var.ssh_public_key}\n${tls_private_key.ssh.public_key_openssh}"
    user_data           = base64encode(templatefile("${path.module}/scripts/cloud-init.yaml", {
      ssh_username   = var.ssh_username
      hyperthreading = true
      install_aeron  = var.install_aeron
      java_version   = var.java_version
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
    role         = "controller"
    aeron        = "true"
  }

  lifecycle {
    ignore_changes = [
      source_details[0].source_id,
    ]
  }
}

# =============================================================================
# Benchmark Nodes (Private Subnet - Client/Receiver)
# =============================================================================
resource "oci_core_instance" "benchmark" {
  count               = var.benchmark_node_count
  availability_domain = var.benchmark_ad
  compartment_id      = var.compartment_ocid
  shape               = var.benchmark_shape
  display_name        = "${local.cluster_name}-benchmark-${count.index + 1}"

  dynamic "shape_config" {
    for_each = local.is_benchmark_flex_shape ? [1] : []
    content {
      ocpus         = var.benchmark_ocpus
      memory_in_gbs = var.benchmark_memory_gb
    }
  }

  dynamic "platform_config" {
    for_each = local.benchmark_platform_config_type != null || !var.hyperthreading ? [1] : []
    content {
      type                                           = local.benchmark_platform_config_type != null ? local.benchmark_platform_config_type : "AMD_VM"
      is_symmetric_multi_threading_enabled           = var.hyperthreading
      are_virtual_instructions_enabled               = false
      is_access_control_service_enabled              = false
      is_input_output_memory_management_unit_enabled = false
    }
  }

  source_details {
    source_type             = "image"
    source_id               = local.compute_image
    boot_volume_size_in_gbs = var.benchmark_boot_volume_size_gb
    boot_volume_vpus_per_gb = 20
  }

  create_vnic_details {
    subnet_id        = local.private_subnet_id
    assign_public_ip = false
    hostname_label   = "benchmark-${count.index + 1}"
  }

  metadata = {
    ssh_authorized_keys = "${var.ssh_public_key}\n${tls_private_key.ssh.public_key_openssh}"
    user_data           = base64encode(templatefile("${path.module}/scripts/cloud-init.yaml", {
      ssh_username   = var.ssh_username
      hyperthreading = var.hyperthreading
      install_aeron  = var.install_aeron
      java_version   = var.java_version
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
    role         = count.index == 0 ? "client" : "receiver"
    node_index   = tostring(count.index + 1)
    aeron        = "true"
  }

  lifecycle {
    ignore_changes = [
      source_details[0].source_id,
    ]
  }
}

# =============================================================================
# Failover Node (Private Subnet - Different AD)
# =============================================================================
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
    for_each = local.failover_platform_config_type != null || !var.hyperthreading ? [1] : []
    content {
      type                                           = local.failover_platform_config_type != null ? local.failover_platform_config_type : "AMD_VM"
      is_symmetric_multi_threading_enabled           = var.hyperthreading
      are_virtual_instructions_enabled               = false
      is_access_control_service_enabled              = false
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
    subnet_id        = local.private_subnet_id
    assign_public_ip = false
    hostname_label   = "failover"
  }

  metadata = {
    ssh_authorized_keys = "${var.ssh_public_key}\n${tls_private_key.ssh.public_key_openssh}"
    user_data           = base64encode(templatefile("${path.module}/scripts/cloud-init.yaml", {
      ssh_username   = var.ssh_username
      hyperthreading = var.hyperthreading
      install_aeron  = var.install_aeron
      java_version   = var.java_version
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

# =============================================================================
# Provisioner for Controller Node
# =============================================================================
resource "null_resource" "controller_provisioner" {
  depends_on = [oci_core_instance.controller]

  triggers = {
    instance_id = oci_core_instance.controller.id
  }

  connection {
    type        = "ssh"
    host        = local.controller_host
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
      "echo 'Controller node provisioning complete'",
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
      var.install_aeron ? "cd /opt/aeron/playbooks && ansible-playbook -i 'localhost,' -c local site.yml -e 'hyperthreading=true java_version=${var.java_version} aeron_git_repo=${var.aeron_git_repo} aeron_git_branch=${var.aeron_git_branch} node_role=controller'" : "echo 'Skipping Aeron installation'",
    ]
  }
}

# =============================================================================
# Provisioner for Benchmark Nodes (via Controller bastion)
# =============================================================================
resource "null_resource" "benchmark_provisioner" {
  count      = var.benchmark_node_count
  depends_on = [oci_core_instance.benchmark, null_resource.controller_provisioner]

  triggers = {
    instance_id = oci_core_instance.benchmark[count.index].id
  }

  connection {
    type        = "ssh"
    host        = oci_core_instance.benchmark[count.index].private_ip
    user        = var.ssh_username
    private_key = tls_private_key.ssh.private_key_pem
    timeout     = "15m"

    bastion_host        = local.controller_host
    bastion_user        = var.ssh_username
    bastion_private_key = tls_private_key.ssh.private_key_pem
  }

  provisioner "remote-exec" {
    inline = [
      "#!/bin/bash",
      "set -e",
      "echo 'Waiting for cloud-init to complete...'",
      "cloud-init status --wait || true",
      "echo 'Benchmark node ${count.index + 1} provisioning complete'",
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
      var.install_aeron ? "cd /opt/aeron/playbooks && ansible-playbook -i 'localhost,' -c local site.yml -e 'hyperthreading=${var.hyperthreading} java_version=${var.java_version} aeron_git_repo=${var.aeron_git_repo} aeron_git_branch=${var.aeron_git_branch} node_role=${count.index == 0 ? "client" : "receiver"}'" : "echo 'Skipping Aeron installation'",
    ]
  }
}

# =============================================================================
# Provisioner for Failover Node (via Controller bastion)
# =============================================================================
resource "null_resource" "failover_provisioner" {
  count      = var.enable_failover_node ? 1 : 0
  depends_on = [oci_core_instance.failover, null_resource.controller_provisioner]

  triggers = {
    instance_id = oci_core_instance.failover[0].id
  }

  connection {
    type        = "ssh"
    host        = oci_core_instance.failover[0].private_ip
    user        = var.ssh_username
    private_key = tls_private_key.ssh.private_key_pem
    timeout     = "15m"

    bastion_host        = local.controller_host
    bastion_user        = var.ssh_username
    bastion_private_key = tls_private_key.ssh.private_key_pem
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
      var.install_aeron ? "cd /opt/aeron/playbooks && ansible-playbook -i 'localhost,' -c local site.yml -e 'hyperthreading=${var.hyperthreading} java_version=${var.java_version} aeron_git_repo=${var.aeron_git_repo} aeron_git_branch=${var.aeron_git_branch} node_role=failover'" : "echo 'Skipping Aeron installation'",
    ]
  }
}
