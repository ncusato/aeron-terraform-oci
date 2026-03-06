#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# Runs echo or cluster across driver modes and compares results.
# Usage:
#   ./run-driver-matrix.sh [echo|cluster]
# Env:
#   MATRIX_MODES="java,c,java_vma,c_vma"
#   CONFIG_FILE="./config/benchmark-config.env"

TARGET="${1:-echo}"
MATRIX_MODES="${MATRIX_MODES:-java,java_vma,c,c_vma}"
CONFIG_FILE="${CONFIG_FILE:-./config/benchmark-config.env}"
STATUS_FILE="${STATUS_FILE:-}"
SUMMARY_FILE="${SUMMARY_FILE:-./driver-matrix-summary.csv}"

if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "Config file not found: ${CONFIG_FILE}" >&2
  exit 1
fi

# Export all config values so wrappers can consume them.
set -a
# shellcheck source=/dev/null
source "${CONFIG_FILE}"
set +a

wrapper=""
if [[ "${TARGET}" == "echo" ]]; then
  wrapper="./wrapper-echo-unified.sh"
elif [[ "${TARGET}" == "cluster" ]]; then
  wrapper="./wrapper-cluster-unified.sh"
else
  echo "Target must be 'echo' or 'cluster'" >&2
  exit 1
fi

IFS=',' read -r -a modes <<< "${MATRIX_MODES}"
archives=()
summary_tmp="$(mktemp)"
run_failures=0

status() {
  local msg="$1"
  echo "${msg}"
  if [[ -n "${STATUS_FILE}" ]]; then
    printf '%s %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "${msg}" >> "${STATUS_FILE}"
  fi
}

echo "mode,status,notes" > "${summary_tmp}"

for mode in "${modes[@]}"; do
  mode="$(echo "${mode}" | xargs)"
  context="${TARGET}-matrix-${mode}"
  log="/tmp/${context}.log"
  status "=== Running ${TARGET} mode=${mode} context=${context} ==="

  if [[ "${TARGET}" == "echo" ]]; then
    if CLIENT_MODE="${mode}" SERVER_MODE="${mode}" CONTEXT="${context}" \
      bash "${wrapper}" 2>&1 | tee "${log}"; then
      echo "${mode},ok,wrapper-run-success" >> "${summary_tmp}"
    else
      run_failures=$((run_failures + 1))
      echo "${mode},failed,wrapper-run-failed-see-${log}" >> "${summary_tmp}"
      status "Mode ${mode} failed; continuing with next mode."
      continue
    fi
  else
    if CLUSTER_CLIENT_MODE="${mode}" CLUSTER_SERVER_MODE="${mode}" CLUSTER_CONTEXT="${context}" \
      bash "${wrapper}" "${CONFIG_FILE}" 2>&1 | tee "${log}"; then
      echo "${mode},ok,wrapper-run-success" >> "${summary_tmp}"
    else
      run_failures=$((run_failures + 1))
      echo "${mode},failed,wrapper-run-failed-see-${log}" >> "${summary_tmp}"
      status "Mode ${mode} failed; continuing with next mode."
      continue
    fi
  fi

  test_dir="$(sed -n 's/.*test_dir=\(aeron-[0-9A-Za-z-]*\).*/\1/p' "${log}" | head -n 1 | tr -d '\r' || true)"
  if [[ -n "${test_dir}" ]]; then
    client_tar="./${test_dir}-client.tar.gz"
    if [[ -f "${client_tar}" ]]; then
      archives+=("${client_tar}")
    fi
  fi

  if [[ "${#archives[@]}" -eq 0 ]]; then
    latest_client="$(ls -1t ./aeron-${TARGET}-*-client.tar.gz 2>/dev/null | head -n 1 || true)"
    if [[ -n "${latest_client}" && -f "${latest_client}" ]]; then
      archives+=("${latest_client}")
    fi
  fi
done

if [[ "${#archives[@]}" -eq 0 ]]; then
  status "No client archives found to compare."
  cp -f "${summary_tmp}" "${SUMMARY_FILE}"
  exit 1
fi

status "=== Comparison output ==="
bash ./aggregate-compare-results.sh "${archives[@]}" | tee -a "${summary_tmp}" | tee "${SUMMARY_FILE}"

if [[ "${run_failures}" -gt 0 ]]; then
  status "Matrix completed with ${run_failures} failed mode(s)."
else
  status "Matrix completed successfully for all modes."
fi
