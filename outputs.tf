output "cluster_name" {
  description = "Cluster name"
  value       = local.cluster_name
}

output "primary_instance_id" {
  description = "OCID of the controller instance"
  value       = oci_core_instance.primary.id
}

output "primary_public_ip" {
  description = "Public IP of the controller instance (in public subnet)"
  value       = var.private_deployment ? null : oci_core_instance.primary.public_ip
}

output "primary_private_ip" {
  description = "Private IP of the controller instance"
  value       = oci_core_instance.primary.private_ip
}

output "primary_ssh_command" {
  description = "SSH command to connect to controller node"
  value       = var.private_deployment ? "ssh -i <your-key> ${var.ssh_username}@${oci_core_instance.primary.private_ip}" : "ssh -i <your-key> ${var.ssh_username}@${oci_core_instance.primary.public_ip}"
}

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
  value       = var.enable_failover_node ? "ssh -i <your-key> -J ${var.ssh_username}@${var.private_deployment ? oci_core_instance.primary.private_ip : oci_core_instance.primary.public_ip} ${var.ssh_username}@${oci_core_instance.failover[0].private_ip}" : null
}

output "vcn_id" {
  description = "VCN OCID"
  value       = local.vcn_id
}

output "public_subnet_id" {
  description = "Public Subnet OCID (controller)"
  value       = local.public_subnet_id
}

output "private_subnet_id" {
  description = "Private Subnet OCID (failover)"
  value       = local.private_subnet_id
}

output "generated_ssh_private_key" {
  description = "Generated SSH private key for cluster communication"
  value       = tls_private_key.ssh.private_key_pem
  sensitive   = true
}

output "aeron_info" {
  description = "Aeron deployment information"
  value = {
    git_repo             = var.aeron_git_repo
    git_branch           = var.aeron_git_branch != "" ? var.aeron_git_branch : "master (latest)"
    java_version         = var.java_version
    hyperthreading       = var.hyperthreading
    controller_ocpus     = var.primary_ocpus
    failover_enabled     = var.enable_failover_node
    failover_ocpus       = var.enable_failover_node ? var.failover_ocpus : null
  }
}

output "benchmark_command" {
  description = "Command to run Aeron benchmarks"
  value       = "ssh ${var.ssh_username}@${var.private_deployment ? oci_core_instance.primary.private_ip : oci_core_instance.primary.public_ip} 'cd /opt/aeron && ./run-benchmark.sh'"
}
