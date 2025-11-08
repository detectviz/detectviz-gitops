#!/usr/bin/env bash
set -euo pipefail

TF_DIR=${TF_DIR:-../terraform}

if ! command -v terraform >/dev/null 2>&1; then
  echo "terraform not found in PATH" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not found in PATH" >&2
  exit 1
fi

TF_OUTPUT=$(terraform -chdir="${TF_DIR}" output -json)

get_field() {
  local field=$1
  echo "${TF_OUTPUT}" | jq -r "${field}" | sed '/^null$/d'
}

cluster=$(get_field '.cluster_summary.value.cluster_name')
k8s_version=$(get_field '.cluster_summary.value.kubernetes_version')
proxmox_host=$(get_field '.cluster_summary.value.proxmox_host')

if [[ -z "${cluster}" ]]; then
  echo "missing cluster_name in terraform outputs" >&2
  exit 1
fi

if [[ -z "${k8s_version}" ]]; then
  echo "missing kubernetes_version in terraform outputs" >&2
  exit 1
fi

if [[ -z "${proxmox_host}" ]]; then
  echo "missing proxmox_host in terraform outputs" >&2
  exit 1
fi

echo "# kubectl label commands generated from terraform outputs"
echo "# verify each command then execute to align virtualization → orchestration labels"
echo ""

echo "${TF_OUTPUT}" | jq -r \
  --arg cluster "${cluster}" \
  --arg k8s_version "${k8s_version}" \
  --arg proxmox_host "${proxmox_host}" '
    (.master_nodes_details.value + .worker_nodes_details.value)
    | to_entries[]
    | "kubectl label node \(.value.hostname) --overwrite \\
  app.kubernetes.io/name=detectviz-node \\
  app.kubernetes.io/instance=\($cluster)-\(.key) \\
  app.kubernetes.io/version=\($k8s_version) \\
  app.kubernetes.io/component=\(.value.node_role) \\
  app.kubernetes.io/part-of=\($cluster) \\
  app.kubernetes.io/managed-by=terraform \\
  detectviz.io/proxmox-host=\(.value.host_id // $proxmox_host)"
  '
