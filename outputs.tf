output "cluster_name" {
  description = "Cluster name"
  value       = local.cluster_name
}

# =============================================================================
# Controller Node Outputs
# =============================================================================
output "controller_instance_id" {
  description = "OCID of the controller instance"
  value       = oci_core_instance.controller.id
}

output "controller_public_ip" {
  description = "Public IP of the controller instance (in public subnet)"
  value       = var.private_deployment ? null : oci_core_instance.controller.public_ip
}

output "controller_private_ip" {
  description = "Private IP of the controller instance"
  value       = oci_core_instance.controller.private_ip
}

output "controller_ssh_command" {
  description = "SSH command to connect to controller node"
  value       = var.private_deployment ? "ssh -i <your-key> ${var.ssh_username}@${oci_core_instance.controller.private_ip}" : "ssh -i <your-key> ${var.ssh_username}@${oci_core_instance.controller.public_ip}"
}

# =============================================================================
# Benchmark Nodes Outputs
# =============================================================================
output "benchmark_instance_ids" {
  description = "OCIDs of the benchmark instances"
  value       = oci_core_instance.benchmark[*].id
}

output "benchmark_private_ips" {
  description = "Private IPs of the benchmark instances (in private subnet)"
  value       = oci_core_instance.benchmark[*].private_ip
}

output "benchmark_ssh_commands" {
  description = "SSH commands to connect to benchmark nodes (via controller bastion)"
  value = [
    for idx, ip in oci_core_instance.benchmark[*].private_ip :
    "ssh -i <your-key> -J ${var.ssh_username}@${var.private_deployment ? oci_core_instance.controller.private_ip : oci_core_instance.controller.public_ip} ${var.ssh_username}@${ip}"
  ]
}

output "client_node_ip" {
  description = "Private IP of the client node (benchmark-1)"
  value       = oci_core_instance.benchmark[0].private_ip
}

output "receiver_node_ip" {
  description = "Private IP of the receiver node (benchmark-2)"
  value       = var.benchmark_node_count >= 2 ? oci_core_instance.benchmark[1].private_ip : null
}

# =============================================================================
# Failover Node Outputs
# =============================================================================
output "failover_instance_id" {
  description = "OCID of the failover instance"
  value       = var.enable_failover_node ? oci_core_instance.failover[0].id : null
}

output "failover_private_ip" {
  description = "Private IP of the failover instance (in private subnet)"
  value       = var.enable_failover_node ? oci_core_instance.failover[0].private_ip : null
}

output "failover_ssh_command" {
  description = "SSH command to connect to failover node (via controller bastion)"
  value       = var.enable_failover_node ? "ssh -i <your-key> -J ${var.ssh_username}@${var.private_deployment ? oci_core_instance.controller.private_ip : oci_core_instance.controller.public_ip} ${var.ssh_username}@${oci_core_instance.failover[0].private_ip}" : null
}

# =============================================================================
# Network Outputs
# =============================================================================
output "vcn_id" {
  description = "VCN OCID"
  value       = local.vcn_id
}

output "public_subnet_id" {
  description = "Public Subnet OCID (controller)"
  value       = local.public_subnet_id
}

output "private_subnet_id" {
  description = "Private Subnet OCID (benchmark/failover nodes)"
  value       = local.private_subnet_id
}

# =============================================================================
# SSH Key Outputs
# =============================================================================
output "generated_ssh_private_key" {
  description = "Generated SSH private key (for provisioning)"
  value       = tls_private_key.ssh.private_key_pem
  sensitive   = true
}

# =============================================================================
# Aeron Information
# =============================================================================
output "aeron_info" {
  description = "Aeron deployment information"
  value = {
    git_repo             = var.aeron_git_repo
    git_branch           = var.aeron_git_branch != "" ? var.aeron_git_branch : "master (latest)"
    java_version         = var.java_version
    hyperthreading       = var.hyperthreading
    controller_ocpus     = var.controller_ocpus
    benchmark_node_count = var.benchmark_node_count
    benchmark_ocpus      = var.benchmark_ocpus
    failover_enabled     = var.enable_failover_node
    failover_ocpus       = var.enable_failover_node ? var.failover_ocpus : null
  }
}

output "benchmark_command" {
  description = "Command to run Aeron benchmarks from controller"
  value       = "ssh ${var.ssh_username}@${var.private_deployment ? oci_core_instance.controller.private_ip : oci_core_instance.controller.public_ip} 'cd /opt/aeron && ./run-benchmark.sh'"
}

# =============================================================================
# Node Summary
# =============================================================================
output "node_summary" {
  description = "Summary of all deployed nodes"
  value = {
    controller = {
      hostname   = "controller"
      public_ip  = var.private_deployment ? null : oci_core_instance.controller.public_ip
      private_ip = oci_core_instance.controller.private_ip
      ocpus      = var.controller_ocpus
      role       = "orchestrator"
    }
    benchmark_nodes = [
      for idx, instance in oci_core_instance.benchmark : {
        hostname   = "benchmark-${idx + 1}"
        private_ip = instance.private_ip
        ocpus      = var.benchmark_ocpus
        role       = idx == 0 ? "client" : "receiver"
      }
    ]
    failover = var.enable_failover_node ? {
      hostname   = "failover"
      private_ip = oci_core_instance.failover[0].private_ip
      ocpus      = var.failover_ocpus
      role       = "failover"
    } : null
  }
}
