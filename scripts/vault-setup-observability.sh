#!/bin/bash
# Vault 自動配置腳本 - Observability Stack Secrets
# 
# 此腳本自動生成並寫入所有 Observability Stack 所需的 secrets 到 Vault
#
# 使用方式:
#   ./scripts/vault-setup-observability.sh

set -euo pipefail

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 檢查 vault CLI
if ! command -v vault &> /dev/null; then
    log_error "vault CLI 未安裝，請先安裝: https://www.vaultproject.io/downloads"
    exit 1
fi

# 檢查 Vault 連接
if ! vault status &> /dev/null; then
    log_error "無法連接到 Vault，請檢查 VAULT_ADDR 和 VAULT_TOKEN 環境變數"
    exit 1
fi

log_info "=========================================="
log_info "Detectviz Observability Stack - Vault Setup"
log_info "=========================================="
log_info ""

# 確認執行
read -p "確認要在 Vault 中創建 Observability Secrets? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_warn "操作已取消"
    exit 0
fi

log_info ""
log_info "生成隨機密碼..."

# 生成所有密碼
POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
APP_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
REPMGR_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
GRAFANA_DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-24)
KEYCLOAK_CLIENT_SECRET=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
MINIO_ROOT_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
MIMIR_SECRET_KEY=$(openssl rand -base64 40 | tr -d "=+/" | cut -c1-40)

# 計算 MD5 (用於 Pgpool)
POSTGRES_MD5="md5$(echo -n "${POSTGRES_PASSWORD}postgres" | md5sum | cut -d' ' -f1)"
APP_MD5="md5$(echo -n "${APP_PASSWORD}app" | md5sum | cut -d' ' -f1)"

log_info "寫入 PostgreSQL secrets 到 Vault..."
vault kv put secret/monitoring/postgresql \
  postgres-password="${POSTGRES_PASSWORD}" \
  app-password="${APP_PASSWORD}" \
  repmgr-password="${REPMGR_PASSWORD}" \
  postgresUser="postgres" \
  postgresPasswordMd5="${POSTGRES_MD5}" \
  appUser="app" \
  appPasswordMd5="${APP_MD5}" \
  init-grafana-sql="CREATE DATABASE grafana; CREATE USER grafana WITH PASSWORD '${GRAFANA_DB_PASSWORD}'; GRANT ALL PRIVILEGES ON DATABASE grafana TO grafana;"

log_info "寫入 Grafana secrets 到 Vault..."
vault kv put secret/monitoring/grafana \
  admin-user="admin" \
  admin-password="${GRAFANA_ADMIN_PASSWORD}" \
  db-user="grafana" \
  db-password="${GRAFANA_DB_PASSWORD}" \
  keycloak-client-secret="${KEYCLOAK_CLIENT_SECRET}"

log_info "寫入 Minio secrets 到 Vault..."
vault kv put secret/monitoring/minio \
  root-user="admin" \
  root-password="${MINIO_ROOT_PASSWORD}" \
  mimir-access-key="mimir" \
  mimir-secret-key="${MIMIR_SECRET_KEY}"

log_info ""
log_info "=========================================="
log_info "✅ 所有 Secrets 已成功寫入 Vault"
log_info "=========================================="
log_info ""
log_info "密碼備份 (請妥善保存):"
log_info "----------------------------------------"
log_info "PostgreSQL postgres: ${POSTGRES_PASSWORD}"
log_info "PostgreSQL app: ${APP_PASSWORD}"
log_info "PostgreSQL repmgr: ${REPMGR_PASSWORD}"
log_info "Grafana admin: ${GRAFANA_ADMIN_PASSWORD}"
log_info "Grafana DB: ${GRAFANA_DB_PASSWORD}"
log_info "Keycloak client secret: ${KEYCLOAK_CLIENT_SECRET}"
log_info "Minio root: ${MINIO_ROOT_PASSWORD}"
log_info "Mimir secret key: ${MIMIR_SECRET_KEY}"
log_info "----------------------------------------"
log_info ""
log_warn "重要: 請將上述密碼保存到安全的密碼管理器中！"
log_info ""
log_info "下一步:"
log_info "  1. 驗證 Vault secrets: vault kv get secret/monitoring/postgresql"
log_info "  2. 部署 Observability ApplicationSet"
log_info "  3. 檢查 ExternalSecrets: kubectl get externalsecrets -n monitoring"
log_info ""
