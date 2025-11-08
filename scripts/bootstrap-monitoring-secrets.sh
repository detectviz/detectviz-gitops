#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: ${0##*/} [--namespace <namespace>] [--env-file <file>]

Environment variables (or entries inside --env-file) must define:
  GRAFANA_ADMIN_USER
  GRAFANA_ADMIN_PASSWORD
  GRAFANA_DB_NAME
  GRAFANA_DB_USER
  GRAFANA_DB_PASSWORD
USAGE
}

NAMESPACE="monitoring"
ENV_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace)
      shift
      NAMESPACE="${1:-}"
      [[ -n "$NAMESPACE" ]] || { echo "error: --namespace requires a value" >&2; exit 1; }
      ;;
    --env-file)
      shift
      ENV_FILE="${1:-}"
      [[ -n "$ENV_FILE" ]] || { echo "error: --env-file requires a value" >&2; exit 1; }
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

if [[ -n "$ENV_FILE" ]]; then
  if [[ ! -f "$ENV_FILE" ]]; then
    echo "error: env file '$ENV_FILE' not found" >&2
    exit 1
  fi
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

for bin in kubectl; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "error: required binary '$bin' not found in PATH" >&2
    exit 1
  fi
done

: "${GRAFANA_ADMIN_USER:?GRAFANA_ADMIN_USER must be set}"
: "${GRAFANA_ADMIN_PASSWORD:?GRAFANA_ADMIN_PASSWORD must be set}"
: "${GRAFANA_DB_NAME:?GRAFANA_DB_NAME must be set}"
: "${GRAFANA_DB_USER:?GRAFANA_DB_USER must be set}"
: "${GRAFANA_DB_PASSWORD:?GRAFANA_DB_PASSWORD must be set}"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

echo "[monitoring-secrets] syncing grafana-admin secret in namespace '$NAMESPACE'"
kubectl -n "$NAMESPACE" create secret generic grafana-admin \
  --from-literal=admin-user="$GRAFANA_ADMIN_USER" \
  --from-literal=admin-password="$GRAFANA_ADMIN_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "[monitoring-secrets] syncing grafana-database secret in namespace '$NAMESPACE'"
kubectl -n "$NAMESPACE" create secret generic grafana-database \
  --from-literal=GF_DATABASE_NAME="$GRAFANA_DB_NAME" \
  --from-literal=GF_DATABASE_USER="$GRAFANA_DB_USER" \
  --from-literal=GF_DATABASE_PASSWORD="$GRAFANA_DB_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "[monitoring-secrets] completed"
