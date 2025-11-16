# Vault Secrets 配置指南

本文檔說明如何在 Vault 中配置 Observability Stack 所需的 Secrets。

## 架構說明

Detectviz 使用 **External Secrets Operator + Vault** 來管理所有 Kubernetes Secrets：

```
Vault (secret/data/monitoring/*)
  ↓ (External Secrets Operator)
Kubernetes Secrets (monitoring namespace)
  ↓
應用 Pods (Grafana, PostgreSQL, Minio, etc.)
```

## Vault 路徑結構

所有 Observability Stack 的 secrets 儲存在以下路徑：

```
secret/data/monitoring/postgresql
secret/data/monitoring/grafana
secret/data/monitoring/minio
```

## 必要配置

### 1. PostgreSQL Secrets

**Vault 路徑**: `secret/data/monitoring/postgresql`

**必要欄位**:
```json
{
  "postgres-password": "隨機生成32字符密碼",
  "app-password": "隨機生成32字符密碼",
  "repmgr-password": "隨機生成32字符密碼",
  "postgresUser": "postgres",
  "postgresPasswordMd5": "md5<postgres-password的md5>postgres",
  "appUser": "app",
  "appPasswordMd5": "md5<app-password的md5>app",
  "init-grafana-sql": "CREATE DATABASE grafana; CREATE USER grafana WITH PASSWORD 'grafana-db-password'; GRANT ALL PRIVILEGES ON DATABASE grafana TO grafana;"
}
```

**配置指令**:
```bash
# 生成密碼
POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
APP_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
REPMGR_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
GRAFANA_DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)

# 計算 MD5 (用於 Pgpool)
POSTGRES_MD5="md5$(echo -n "${POSTGRES_PASSWORD}postgres" | md5sum | cut -d' ' -f1)"
APP_MD5="md5$(echo -n "${APP_PASSWORD}app" | md5sum | cut -d' ' -f1)"

# 寫入 Vault
vault kv put secret/monitoring/postgresql \
  postgres-password="${POSTGRES_PASSWORD}" \
  app-password="${APP_PASSWORD}" \
  repmgr-password="${REPMGR_PASSWORD}" \
  postgresUser="postgres" \
  postgresPasswordMd5="${POSTGRES_MD5}" \
  appUser="app" \
  appPasswordMd5="${APP_MD5}" \
  init-grafana-sql="CREATE DATABASE grafana; CREATE USER grafana WITH PASSWORD '${GRAFANA_DB_PASSWORD}'; GRANT ALL PRIVILEGES ON DATABASE grafana TO grafana;"
```

### 2. Grafana Secrets

**Vault 路徑**: `secret/data/monitoring/grafana`

**必要欄位**:
```json
{
  "admin-user": "admin",
  "admin-password": "隨機生成24字符密碼",
  "db-user": "grafana",
  "db-password": "與PostgreSQL init-grafana-sql中的密碼一致",
  "keycloak-client-secret": "從Keycloak獲取的client secret (可選)"
}
```

**配置指令**:
```bash
# 生成密碼
ADMIN_PASSWORD=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-24)
GRAFANA_DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
KEYCLOAK_CLIENT_SECRET=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)

# 寫入 Vault
vault kv put secret/monitoring/grafana \
  admin-user="admin" \
  admin-password="${ADMIN_PASSWORD}" \
  db-user="grafana" \
  db-password="${GRAFANA_DB_PASSWORD}" \
  keycloak-client-secret="${KEYCLOAK_CLIENT_SECRET}"
```

⚠️ **重要**: `db-password` 必須與 PostgreSQL 的 `init-grafana-sql` 中的密碼一致！

### 3. Minio Secrets

**Vault 路徑**: `secret/data/monitoring/minio`

**必要欄位**:
```json
{
  "root-user": "admin",
  "root-password": "隨機生成32字符密碼",
  "mimir-access-key": "mimir",
  "mimir-secret-key": "隨機生成40字符密碼"
}
```

**配置指令**:
```bash
# 生成密碼
ROOT_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
MIMIR_SECRET_KEY=$(openssl rand -base64 40 | tr -d "=+/" | cut -c1-40)

# 寫入 Vault
vault kv put secret/monitoring/minio \
  root-user="admin" \
  root-password="${ROOT_PASSWORD}" \
  mimir-access-key="mimir" \
  mimir-secret-key="${MIMIR_SECRET_KEY}"
```

## 驗證配置

### 檢查 Vault 中的 Secrets

```bash
# 檢查 PostgreSQL secrets
vault kv get secret/monitoring/postgresql

# 檢查 Grafana secrets
vault kv get secret/monitoring/grafana

# 檢查 Minio secrets
vault kv get secret/monitoring/minio
```

### 檢查 ExternalSecrets 狀態

```bash
# 檢查所有 ExternalSecrets
kubectl get externalsecrets -n monitoring

# 檢查特定 ExternalSecret 的詳細狀態
kubectl describe externalsecret postgresql-credentials -n monitoring
kubectl describe externalsecret grafana-db-creds -n monitoring
kubectl describe externalsecret minio-root-credentials -n monitoring

# 檢查生成的 Kubernetes Secrets
kubectl get secrets -n monitoring
```

### 檢查 Secret 內容

```bash
# PostgreSQL
kubectl get secret detectviz-postgresql-admin -n monitoring -o yaml

# Grafana
kubectl get secret grafana-admin -n monitoring -o yaml
kubectl get secret grafana-database -n monitoring -o yaml

# Minio
kubectl get secret minio-root-credentials -n monitoring -o yaml
kubectl get secret minio-mimir-user -n monitoring -o yaml
```

## 故障排除

### ExternalSecret 狀態為 SecretSyncedError

**問題**: ExternalSecret 無法從 Vault 同步

**檢查步驟**:
```bash
# 1. 檢查 External Secrets Operator logs
kubectl logs -n external-secrets-system deploy/external-secrets

# 2. 檢查 ClusterSecretStore 狀態
kubectl get clustersecretstore vault-backend -o yaml

# 3. 檢查 Vault 路徑是否正確
vault kv get secret/monitoring/postgresql

# 4. 檢查 Vault policy
vault policy read external-secrets-operator
```

**常見原因**:
- Vault 路徑不存在
- Vault policy 權限不足
- ClusterSecretStore 配置錯誤
- Vault token 過期

### Secret 欄位缺失

**問題**: Kubernetes Secret 創建成功但欄位缺失

**檢查**:
```bash
kubectl get secret <secret-name> -n monitoring -o jsonpath='{.data}' | jq
```

**解決**: 確認 Vault 中的欄位名稱與 ExternalSecret 定義一致

### Grafana 無法連接到 PostgreSQL

**問題**: Grafana Pod 啟動失敗，logs 顯示資料庫連接錯誤

**檢查**:
```bash
# 1. 確認 grafana-database Secret 存在且包含所有欄位
kubectl get secret grafana-database -n monitoring -o jsonpath='{.data}' | jq

# 2. 確認 PostgreSQL init-grafana-sql 中的密碼與 Grafana db-password 一致
vault kv get secret/monitoring/postgresql -format=json | jq -r '.data.data."init-grafana-sql"'
vault kv get secret/monitoring/grafana -format=json | jq -r '.data.data."db-password"'

# 3. 檢查 PostgreSQL logs
kubectl logs -n monitoring statefulset/postgresql-postgresql -c postgresql
```

## 自動化腳本 (可選)

可以使用以下腳本自動生成並寫入所有 secrets：

```bash
#!/bin/bash
# vault-setup-observability.sh

set -euo pipefail

# 生成所有密碼
POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
APP_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
REPMGR_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
GRAFANA_DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-24)
KEYCLOAK_CLIENT_SECRET=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
MINIO_ROOT_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
MIMIR_SECRET_KEY=$(openssl rand -base64 40 | tr -d "=+/" | cut -c1-40)

# 計算 MD5
POSTGRES_MD5="md5$(echo -n "${POSTGRES_PASSWORD}postgres" | md5sum | cut -d' ' -f1)"
APP_MD5="md5$(echo -n "${APP_PASSWORD}app" | md5sum | cut -d' ' -f1)"

# 寫入 Vault
vault kv put secret/monitoring/postgresql \
  postgres-password="${POSTGRES_PASSWORD}" \
  app-password="${APP_PASSWORD}" \
  repmgr-password="${REPMGR_PASSWORD}" \
  postgresUser="postgres" \
  postgresPasswordMd5="${POSTGRES_MD5}" \
  appUser="app" \
  appPasswordMd5="${APP_MD5}" \
  init-grafana-sql="CREATE DATABASE grafana; CREATE USER grafana WITH PASSWORD '${GRAFANA_DB_PASSWORD}'; GRANT ALL PRIVILEGES ON DATABASE grafana TO grafana;"

vault kv put secret/monitoring/grafana \
  admin-user="admin" \
  admin-password="${GRAFANA_ADMIN_PASSWORD}" \
  db-user="grafana" \
  db-password="${GRAFANA_DB_PASSWORD}" \
  keycloak-client-secret="${KEYCLOAK_CLIENT_SECRET}"

vault kv put secret/monitoring/minio \
  root-user="admin" \
  root-password="${MINIO_ROOT_PASSWORD}" \
  mimir-access-key="mimir" \
  mimir-secret-key="${MIMIR_SECRET_KEY}"

echo "✅ 所有 Secrets 已成功寫入 Vault"
echo ""
echo "密碼備份 (請妥善保存):"
echo "PostgreSQL postgres: ${POSTGRES_PASSWORD}"
echo "Grafana admin: ${GRAFANA_ADMIN_PASSWORD}"
echo "Minio root: ${MINIO_ROOT_PASSWORD}"
```

## 安全性建議

1. **永遠不要**將密碼寫入 Git 儲存庫
2. **定期輪換**所有密碼（建議每 90 天）
3. **使用強密碼**（至少 24 字符，包含大小寫、數字、特殊符號）
4. **限制 Vault 訪問**（使用最小權限原則）
5. **啟用 Vault audit logging**
6. **備份密碼**到安全的密碼管理器（如 1Password, LastPass）

## 相關文檔

- [External Secrets Operator 官方文檔](https://external-secrets.io/)
- [Vault KV Secrets Engine](https://www.vaultproject.io/docs/secrets/kv)
- [ExternalSecret CRD 參考](https://external-secrets.io/latest/api/externalsecret/)
