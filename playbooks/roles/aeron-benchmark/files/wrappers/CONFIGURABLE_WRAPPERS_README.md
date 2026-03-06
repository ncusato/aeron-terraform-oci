# Unified Benchmark Wrappers

This is the simplified learning layout:

- 2 primary wrappers:
  - `/home/ubuntu/benchmarks/scripts/wrapper-echo-unified.sh`
  - `/home/ubuntu/benchmarks/scripts/wrapper-cluster-unified.sh`
- 1 shared config:
  - `/home/ubuntu/benchmarks/scripts/config/benchmark-config.env`
- 1 aggregate/compare tool:
  - `/home/ubuntu/benchmarks/scripts/aggregate-compare-results.sh`
- Optional runner for all driver modes:
  - `/home/ubuntu/benchmarks/scripts/run-driver-matrix.sh`

Existing legacy wrappers remain in place for backward compatibility.

## Driver modes

Set `CLIENT_MODE`/`SERVER_MODE` (echo) or `CLUSTER_CLIENT_MODE`/`CLUSTER_SERVER_MODE` (cluster):

- `java`
- `c`
- `java_vma` (mapped to `java-onload`)
- `c_vma` (mapped to `c-onload`)
- `c-dpdk`

## Echo wrapper (combined)

Default run:

```bash
cd /home/ubuntu/benchmarks/scripts
bash ./wrapper-echo-unified.sh
```

Smoke run:

```bash
BENCH_PROFILE=smoke_288_101k \
CLIENT_MODE=java \
SERVER_MODE=java \
CONTEXT=echo-smoke \
bash ./wrapper-echo-unified.sh
```

Preview config only:

```bash
SHOW_CONFIG_ONLY=1 bash ./wrapper-echo-unified.sh
```

## Cluster wrapper (separate)

Default run:

```bash
cd /home/ubuntu/benchmarks/scripts
bash ./wrapper-cluster-unified.sh ./config/benchmark-config.env
```

Config preview only:

```bash
SHOW_CONFIG_ONLY=1 bash ./wrapper-cluster-unified.sh ./config/benchmark-config.env
```

## Run all driver modes and compare

Echo matrix:

```bash
cd /home/ubuntu/benchmarks/scripts
MATRIX_MODES="java,c,java_vma,c_vma" \
bash ./run-driver-matrix.sh echo
```

Cluster matrix:

```bash
cd /home/ubuntu/benchmarks/scripts
MATRIX_MODES="java,c" \
bash ./run-driver-matrix.sh cluster
```

## Aggregate and compare archives directly

```bash
cd /home/ubuntu/benchmarks/scripts
bash ./aggregate-compare-results.sh \
  ./aeron-echo-YYYY-MM-DD-HH-MM-SS-client.tar.gz \
  ./aeron-echo-YYYY-MM-DD-HH-MM-SS-client.tar.gz
```

Output columns:

- archive
- scenario
- valid_runs
- median_p50_us
- median_p99_us
- median_p999_us
- median_max_us
