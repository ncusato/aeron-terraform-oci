# Aeron Deployment for Oracle Cloud Infrastructure

[![Deploy to Oracle Cloud](https://oci-resourcemanager-plugin.plugins.oci.oraclecloud.com/latest/deploy-to-oracle-cloud.svg)](https://cloud.oracle.com/resourcemanager/stacks/create?zipUrl=https://github.com/ncusato/aeron-terraform-oci/archive/refs/heads/main.zip)

Deploy [Aeron](https://github.com/real-logic/aeron) messaging system on OCI for high-performance benchmarking with optimal configurations.

## Features

- **Hyperthreading disabled by default** - Optimized for low-latency benchmarking
- **10+ OCPU minimum** - Ensures sufficient compute resources for accurate benchmarks
- **Optional failover node** - Deploy a secondary node in a different Availability Domain
- **VCN flexibility** - Use existing VCN or create a new one with proper routing
- **Ansible-based configuration** - Automated Aeron and Java installation
- **Benchmark scripts included** - Ready-to-run latency and throughput tests

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         OCI Region                           │
│  ┌─────────────────────────┐  ┌─────────────────────────┐   │
│  │    Availability Domain 1│  │   Availability Domain 2 │   │
│  │                         │  │                         │   │
│  │  ┌──────────────────┐   │  │  ┌──────────────────┐   │   │
│  │  │  Primary Node    │   │  │  │  Failover Node   │   │   │
│  │  │  - Aeron         │   │  │  │  - Aeron         │   │   │
│  │  │  - Java 21       │   │  │  │  - Java 21       │   │   │
│  │  │  - 10+ OCPUs     │   │  │  │  - 10+ OCPUs     │   │   │
│  │  │  - HT Disabled   │   │  │  │  - HT Disabled   │   │   │
│  │  └──────────────────┘   │  │  └──────────────────┘   │   │
│  │                         │  │       (Optional)        │   │
│  └─────────────────────────┘  └─────────────────────────┘   │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                    VCN (New or Existing)              │   │
│  │  - Internet Gateway    - NAT Gateway                  │   │
│  │  - Service Gateway     - Route Tables                 │   │
│  │  - Security Lists (Aeron ports: 40000-40100 UDP)     │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Quick Start

### Option 1: Deploy via OCI Resource Manager (Recommended)

1. Click the **Deploy to Oracle Cloud** button above
2. Sign in to your OCI tenancy
3. Configure the stack:
   - Select compartment and availability domains
   - Choose compute shapes (minimum 10 OCPUs)
   - Enable failover node if needed
   - Configure or select VCN
4. Review and create the stack
5. Run the Apply job

### Option 2: Deploy via Terraform CLI

```bash
# Clone the repository
git clone https://github.com/ncusato/aeron-terraform-oci.git
cd aeron-terraform-oci

# Create terraform.tfvars
cat > terraform.tfvars << EOF
tenancy_ocid     = "ocid1.tenancy.oc1..xxx"
region           = "us-phoenix-1"
compartment_ocid = "ocid1.compartment.oc1..xxx"
ssh_public_key   = "ssh-rsa AAAA..."
primary_ad       = "xxx:PHX-AD-1"
primary_ocpus    = 10

# Optional: Enable failover
enable_failover_node = true
failover_ad          = "xxx:PHX-AD-2"
EOF

# Deploy
terraform init
terraform plan
terraform apply
```

## Configuration Options

### Required Variables

| Variable | Description |
|----------|-------------|
| `compartment_ocid` | Target compartment for deployment |
| `ssh_public_key` | SSH public key for instance access |
| `primary_ad` | Availability Domain for primary node |

### Node Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `primary_shape` | `VM.Standard.E5.Flex` | Compute shape |
| `primary_ocpus` | `10` | Number of OCPUs (min: 10) |
| `primary_memory_gb` | `64` | Memory in GB |
| `hyperthreading` | `false` | SMT setting (disabled for benchmarking) |

### Failover Node

| Variable | Default | Description |
|----------|---------|-------------|
| `enable_failover_node` | `false` | Enable failover in different AD |
| `failover_ad` | `""` | AD for failover (must differ from primary) |
| `failover_ocpus` | `10` | OCPUs for failover node |

### Network Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `use_existing_vcn` | `false` | Use existing VCN |
| `existing_vcn_id` | `""` | VCN OCID (when using existing) |
| `vcn_cidr_block` | `10.0.0.0/16` | CIDR for new VCN |

## Running Benchmarks

After deployment, SSH into the primary node:

```bash
ssh -i <your-key> opc@<primary-ip>
```

### Quick Benchmark

```bash
# Run the full benchmark suite
cd /opt/aeron
./run-benchmark.sh
```

### Manual Benchmarks

```bash
# Terminal 1: Start Media Driver
/opt/aeron/bin/media-driver.sh

# Terminal 2: Start Pong responder
/opt/aeron/bin/pong.sh

# Terminal 3: Run Ping benchmark
/opt/aeron/bin/ping.sh 64 1000000  # 64 bytes, 1M messages
```

### Throughput Test

```bash
# Terminal 1: Media Driver
/opt/aeron/bin/media-driver.sh

# Terminal 2: Throughput publisher
/opt/aeron/bin/throughput.sh 1024 100000000  # 1KB, 100M messages
```

## Performance Tuning

### CPU Isolation

For best results, isolate CPUs for Aeron:

```bash
# Isolate CPUs 2-5 for benchmarking
sudo /opt/aeron/bin/isolate-cpus.sh 2,3,4,5

# Run benchmark on isolated CPUs
taskset -c 2,3 /opt/aeron/bin/ping.sh 64 1000000
```

### NUMA Awareness

```bash
# Run on specific NUMA node
numactl --cpunodebind=0 --membind=0 /opt/aeron/bin/media-driver.sh
```

## Security Considerations

- Aeron UDP ports (40000-40100) are only open within the VCN
- SSH access is open by default; restrict `ssh_cidr` for production
- Use `private_deployment = true` for no public IPs

## Cleanup

### Via Resource Manager
1. Navigate to your stack in OCI Console
2. Run a Destroy job

### Via Terraform CLI
```bash
terraform destroy
```

## Requirements

- OCI tenancy with appropriate IAM policies
- Availability of the selected compute shapes
- For failover: Region with multiple Availability Domains

## OCI Policies

Required IAM policies for deployment:

```
Allow group <group_name> to manage virtual-network-family in compartment <compartment>
Allow group <group_name> to manage instance-family in compartment <compartment>
Allow group <group_name> to use vnics in compartment <compartment>
Allow group <group_name> to use subnets in compartment <compartment>
Allow group <group_name> to use network-security-groups in compartment <compartment>
```

## License

This project is licensed under the Universal Permissive License (UPL) v1.0.

## References

- [Aeron GitHub Repository](https://github.com/real-logic/aeron)
- [OCI Resource Manager](https://docs.oracle.com/en-us/iaas/Content/ResourceManager/home.htm)
- [OCI HPC Quick Start](https://github.com/oracle-quickstart/oci-hpc)
