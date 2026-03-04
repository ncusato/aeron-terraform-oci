# Aeron Deployment for Oracle Cloud Infrastructure

[![Deploy to Oracle Cloud](https://oci-resourcemanager-plugin.plugins.oci.oraclecloud.com/latest/deploy-to-oracle-cloud.svg)](https://cloud.oracle.com/resourcemanager/stacks/create?zipUrl=https://github.com/ncusato/aeron-terraform-oci/releases/latest/download/AeronMessagingTerraform.zip)

Deploy [Aeron](https://github.com/real-logic/aeron) on OCI for high-performance messaging benchmarks. This guide explains how the nodes are configured and how to run and interpret benchmarks.

---

## Table of Contents

1. [Overview](#overview)
2. [Node Roles and Architecture](#node-roles-and-architecture)
3. [How the Benchmark Works](#how-the-benchmark-works)
4. [Quick Start](#quick-start)
5. [Configuration Options](#configuration-options)
6. [Running Benchmarks](#running-benchmarks)
7. [Understanding Results](#understanding-results)
8. [Performance Tuning](#performance-tuning)
9. [Security and Cleanup](#security-and-cleanup)

---

## Overview

This stack deploys:

- **One controller** (orchestrator) in a **public subnet** — small footprint, used for SSH access and running playbooks.
- **Two or more benchmark nodes** (client/receiver) in a **private subnet** — each with at least 10 OCPUs, used for the actual latency and throughput tests.
- **Optional failover node** in the same private subnet but a **different Availability Domain** — same 10 OCPU minimum, for high availability.

Aeron is installed from Git and built on each node. Ansible applies socket buffer tuning, optional CPU isolation, and a fixed benchmark profile (288 bytes @ 101K msg/s) so results are comparable across runs.

---

## Node Roles and Architecture

### What Each Node Does

| Role | Subnet | Default size | Purpose |
|------|--------|--------------|---------|
| **Controller** | Public | 2 OCPUs | Orchestrator only: SSH bastion, runs Ansible, collects results. Does not run the heavy benchmark workload. |
| **Benchmark nodes** | Private | 10+ OCPUs each | **Client** (first node) and **Receiver** (second node). Run the Media Driver, Pong (echo server), and Ping (client) for latency/throughput tests. |
| **Failover** (optional) | Private (different AD) | 10+ OCPUs | Standby node in another Availability Domain for HA. Same Aeron setup as benchmark nodes. |

### Network Layout

```
                    ┌─────────────────────────────────────────────────────────┐
                    │                    OCI Region / VCN                       │
                    │                                                           │
  Internet          │  ┌─────────────────────┐     ┌─────────────────────┐    │
  ───────►          │  │   PUBLIC SUBNET      │     │   PRIVATE SUBNET    │    │
  SSH only          │  │                     │     │                     │    │
                    │  │  ┌───────────────┐  │     │  ┌───────────────┐  │    │
                    │  │  │  CONTROLLER   │  │     │  │  BENCHMARK-1   │  │    │
                    │  │  │  (orchestrator)│  │     │  │  (client)     │  │    │
                    │  │  │  2 OCPU       │  │     │  │  10+ OCPU      │  │    │
                    │  │  └───────┬───────┘  │     │  └───────┬───────┘  │    │
                    │  │          │          │     │          │          │    │
                    │  │          │ SSH      │     │          │ UDP      │    │
                    │  │          │ bastion  │     │          │ Aeron    │    │
                    │  │          ▼          │     │  ┌───────▼───────┐  │    │
                    │  └─────────────────────┘     │  │  BENCHMARK-2   │  │    │
                    │                              │  │  (receiver)    │  │    │
                    │                              │  │  10+ OCPU      │  │    │
                    │                              │  └────────────────┘  │    │
                    │                              │  ┌─────────────────┐  │    │
                    │                              │  │  FAILOVER (opt)  │  │    │
                    │                              │  │  different AD    │  │    │
                    │                              │  └─────────────────┘  │    │
                    │                              └─────────────────────┘    │
                    └─────────────────────────────────────────────────────────┘
```

- You SSH to the **controller** (public IP). From there you can SSH to benchmark and failover nodes (private IPs) for multi-node tests.
- Benchmark nodes talk over the **private subnet** (UDP, Aeron ports 40000–40100).

---

## How the Benchmark Works

### Concepts

1. **Media Driver** — Aeron’s low-latency component that handles shared-memory and network I/O. One instance per machine (or per role) that runs the client or server.
2. **Pong** — Echo server: receives messages and sends them back.
3. **Ping** — Client: sends messages to Pong and measures round-trip latency.

So a **latency benchmark** is: start Media Driver + Pong on the receiver, start Media Driver + Ping on the client; Ping reports percentiles (P50, P99, P999, MAX).

### Single-Node Benchmark (what `run-benchmark.sh` does)

On **one** node (e.g. a benchmark node or the controller):

1. **Preflight** — Apply socket buffer sysctl (so Aeron doesn’t warn about small buffers).
2. **Start Media Driver** — Background process that owns the Aeron channels.
3. **Start Pong** — Echo responder, connected to the same Media Driver.
4. **Run Ping** — Client sends messages to Pong; Ping prints latency percentiles.
5. The script runs a **reference run** (288B @ 101K) then a **sweep** over message sizes (32, 64, 128, … bytes).
6. Results are written under `/opt/aeron/results/`.

This is the simplest way to validate the stack and see typical latency numbers on that machine.

### Two-Node (Client–Receiver) Benchmark

For a more realistic test:

- **Receiver node**: start Media Driver + Pong (server).
- **Client node**: start Media Driver + Ping, pointing at the receiver’s IP/channel.

You run these via SSH from the controller to each private IP. The quickstart guide’s wrapper scripts (e.g. `wrapper-echo-java-two-nodes.sh`) follow this pattern with CPU pinning and tuning.

### Key Metrics

| Metric | Meaning |
|--------|--------|
| **P50** | Median latency (50th percentile). |
| **P99** | 99th percentile — tail latency. |
| **P999** | 99.9th percentile — extreme tail. |
| **MAX** | Maximum observed latency. |

All are typically reported in **microseconds (µs)**. Good tuning keeps P50/P99 low and stable; P999 and MAX can spike due to OS or hypervisor.

### Configuration Applied by Ansible

- **Socket buffers** — 4 MiB (`net.core.rmem/wmem_*`) so Aeron gets the buffer sizes it requests.
- **Reference profile** — 288 bytes, 101K messages/sec, for comparable baselines.
- **Latency-first tuning** — `AERON_NETWORK_PUBLICATION_MAX_MESSAGES_PER_SEND=1`, `AERON_*_IO_VECTOR_CAPACITY=1`, and socket options `AERON_SOCKET_SO_SNDBUF/RCVBUF=2m` to reduce batching jitter.
- **Optional** — GRUB-based CPU isolation (`isolcpus`, `nohz_full`, `rcu_nocbs`, `irqaffinity`) when `apply_cpu_isolation_grub` is enabled (requires reboot).

---

## Quick Start

### Deploy via OCI Resource Manager

1. Click **Deploy to Oracle Cloud** at the top.
2. Sign in and select compartment and region.
3. Set **Controller** AD and shape (default 2 OCPU is fine).
4. Set **Benchmark nodes** AD, count (minimum 2), and shape (10+ OCPUs).
5. Optionally enable **Failover** and choose another AD.
6. Configure or select VCN/subnets, then **Apply**.

### Deploy via Terraform CLI

```bash
git clone https://github.com/ncusato/aeron-terraform-oci.git
cd aeron-terraform-oci
terraform init
# Create terraform.tfvars with compartment_ocid, ssh_public_key, controller_ad, benchmark_ad, etc.
terraform plan
terraform apply
```

After apply, note the **controller public IP** and **benchmark private IPs** from the stack outputs.

---

## Configuration Options

### Controller (orchestrator)

| Variable | Default | Description |
|----------|---------|-------------|
| `controller_ad` | — | Availability Domain for controller. |
| `controller_shape` | `VM.Standard.E5.Flex` | Shape (flex allowed). |
| `controller_ocpus` | `2` | OCPUs (no minimum; orchestrator only). |
| `controller_memory_gb` | `16` | Memory in GB. |

### Benchmark nodes (client/receiver)

| Variable | Default | Description |
|----------|---------|-------------|
| `benchmark_ad` | — | Availability Domain for all benchmark nodes. |
| `benchmark_node_count` | `2` | Number of nodes (minimum 2). |
| `benchmark_shape` | `VM.Standard.E5.Flex` | Shape. |
| `benchmark_ocpus` | `10` | OCPUs per node (minimum 10). |
| `benchmark_memory_gb` | `64` | Memory per node. |

### Failover (optional)

| Variable | Default | Description |
|----------|---------|-------------|
| `enable_failover_node` | `false` | Create failover node. |
| `failover_ad` | — | AD (should differ from benchmark_ad). |
| `failover_ocpus` | `10` | OCPUs (minimum 10). |

### Network

| Variable | Default | Description |
|----------|---------|-------------|
| `use_existing_vcn` | `false` | Use existing VCN. |
| `existing_public_subnet_id` | — | Public subnet for controller. |
| `existing_private_subnet_id` | — | Private subnet for benchmark/failover. |
| `private_deployment` | `false` | Controller without public IP (VPN/FastConnect). |

### Aeron and image

| Variable | Default | Description |
|----------|---------|-------------|
| `install_aeron` | `true` | Install and build Aeron from Git. |
| `aeron_git_repo` | `https://github.com/real-logic/aeron.git` | Aeron repo. |
| `aeron_git_branch` | `""` | Branch/tag (empty = master). |
| `java_version` | `17` | OpenJDK version. |
| `hyperthreading` | `false` | SMT on benchmark/failover (off for latency). |
| `use_default_image` | `true` | Ubuntu 24.04 Minimal image. |

---

## Running Benchmarks

### SSH access

- **Controller**:  
  `ssh -i <your-key> ubuntu@<controller-public-ip>`
- **Benchmark/failover** (via controller):  
  `ssh -i <your-key> -J ubuntu@<controller-public-ip> ubuntu@<benchmark-private-ip>`

### Single-node: automated script

On the controller or any benchmark node:

```bash
cd /opt/aeron
./run-benchmark.sh
```

This runs the reference profile (288B @ 101K) and a sweep. Results go to `/opt/aeron/results/`.

### Manual single-node (three terminals)

```bash
# Terminal 1: Media Driver
/opt/aeron/bin/media-driver.sh

# Terminal 2: Pong (echo server)
/opt/aeron/bin/pong.sh

# Terminal 3: Ping (client) — 288 bytes, 101K messages
/opt/aeron/bin/ping.sh 288 101000
```

### Two-node (client and receiver on different machines)

1. On **receiver** (e.g. benchmark-2): start Media Driver and Pong (channel/endpoint so client can reach it).
2. On **client** (e.g. benchmark-1): start Media Driver and Ping with the receiver’s channel (e.g. `aeron:udp?endpoint=<receiver-ip>:20121`).
3. Use the controller as jump host to SSH to both private IPs.

Exact channel and rate (e.g. 101K) should match your wrapper or script; the Ansible-generated scripts use localhost by default for single-node.

### Throughput (single-node)

```bash
/opt/aeron/bin/media-driver.sh   # in one terminal
/opt/aeron/bin/throughput.sh 1024 100000000   # 1KB, 100M messages
```

---

## Understanding Results

- **P50 (median)** — Typical latency; use for baseline comparison.
- **P99** — Tail latency; target for SLAs.
- **P999 / MAX** — Can spike due to GC, OS, or hypervisor; focus on consistency across runs.

Results are in **microseconds**. Example line:

```text
P50: 37.695 us, P99: 42.655 us, P999: 66.303 us, MAX: 9404.415 us
```

For reproducible baselines, keep the same profile (288B @ 101K), same socket buffer and latency-first tuning, and optionally same CPU isolation across runs.

---

## Performance Tuning

- **Socket buffers** — Already set by Ansible (4 MiB sysctl, 2m for Aeron). Avoid lowering.
- **CPU isolation** — For stricter latency, set `apply_cpu_isolation_grub: true` in Ansible vars, then reboot and use `taskset`/`numactl` to pin Media Driver and Ping/Pong to isolated cores.
- **Hyperthreading** — Disabled by default on benchmark/failover nodes for more stable P99.
- **NUMA** — On multi-socket machines, pin processes to one NUMA node:  
  `numactl --cpunodebind=0 --membind=0 /opt/aeron/bin/media-driver.sh`

---

## Security and Cleanup

- Aeron UDP (40000–40100) is allowed only within the VCN.
- Restrict SSH (e.g. security list or VPN) as needed.
- Use `private_deployment = true` if the controller should have no public IP.

**Destroy stack**

- **Resource Manager**: run a Destroy job on the stack.
- **CLI**: `terraform destroy`

---

## Requirements and References

- OCI tenancy with IAM policies for VCN, instances, and subnets.
- For failover: a second Availability Domain in the region.

**References**

- [Aeron GitHub](https://github.com/real-logic/aeron)
- [OCI Resource Manager](https://docs.oracle.com/en-us/iaas/Content/ResourceManager/home.htm)
- [OCI HPC Quick Start](https://github.com/oracle-quickstart/oci-hpc)

**License** — Universal Permissive License (UPL) v1.0.
