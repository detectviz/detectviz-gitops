# Vault Path 結構規範

**創建日期**: 2025-11-16
**目的**: 定義 DetectViz 平台的 Vault secret 路徑結構，確保安全隔離與最小權限原則

---

## Vault KV v2 Path 架構

DetectViz 使用 **按 namespace 隔離** 的 Vault path 結構，實現 Zero Trust 和 Least Privilege。Secrets 只能透過 Vault 初始化（`./scripts/vault-setup-observability.sh` 或手動 `vault kv put`），再由 ExternalSecrets Operator 投遞到 Kubernetes，任何 `kubectl create secret` 的 bootstrap 腳本都已淘汰：

```bash
secret/
├── postgresql/
│   ├── admin/
│   │   ├── postgres-password     # PostgreSQL superuser password
│   │   ├── app-password           # Application user password
│   │   ├── repmgr-password        # Replication manager password
│   │   ├── postgresUser           # Pgpool auth: postgres user
│   │   ├── postgresPasswordMd5    # Pgpool auth: MD5 hash
│   │   ├── appUser                # Pgpool auth: app user
│   │   └── appPasswordMd5         # Pgpool auth: MD5 hash
│   └── initdb/
│       └── init-grafana-sql       # Grafana database initialization SQL
│
├── keycloak/
│   └── database/
│       └── password               # Keycloak database password
│
├── grafana/
│   ├── admin/
│   │   ├── user                   # Grafana admin username
│   │   └── password               # Grafana admin password
│   ├── database/
│   │   ├── user                   # Grafana database username
│   │   └── password               # Grafana database password
│   └── oauth/
│       └── keycloak-client-secret # Keycloak OAuth2 client secret
│
└── monitoring/
    └── minio/
        ├── root-user              # Minio root username
        ├── root-password          # Minio root password
        ├── mimir-access-key       # Minio user for Mimir (accessKey)
        └── mimir-secret-key       # Minio user for Mimir (secretKey)
```

---

## Vault ACL Policy 設計

### 原則：**按 Namespace 隔離**

每個 namespace 只能訪問自己的 secrets，嚴格禁止跨 namespace 訪問。

### Policy 範例

#### 1. PostgreSQL Namespace Policy

```hcl
# Path: vault-policy-postgresql.hcl
path "secret/data/postgresql/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/postgresql/*" {
  capabilities = ["read", "list"]
}
```

**綁定到**：
- ServiceAccount: `external-secrets` in namespace `postgresql`
- Kubernetes Auth Role: `external-secrets-postgresql`

---

#### 2. Keycloak Namespace Policy

```hcl
# Path: vault-policy-keycloak.hcl
path "secret/data/keycloak/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/keycloak/*" {
  capabilities = ["read", "list"]
}
```

**綁定到**:
- ServiceAccount: `external-secrets` in namespace `keycloak`
- Kubernetes Auth Role: `external-secrets-keycloak`

---

#### 3. Grafana Namespace Policy

```hcl
# Path: vault-policy-grafana.hcl
path "secret/data/grafana/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/grafana/*" {
  capabilities = ["read", "list"]
}
```

**綁定到**:
- ServiceAccount: `external-secrets` in namespace `grafana`
- Kubernetes Auth Role: `external-secrets-grafana`

---

#### 4. Monitoring Namespace Policy

```hcl
# Path: vault-policy-monitoring.hcl
path "secret/data/monitoring/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/monitoring/*" {
  capabilities = ["read", "list"]
}
```

**綁定到**:
- ServiceAccount: `external-secrets` in namespace `monitoring`
- Kubernetes Auth Role: `external-secrets-monitoring`

---

## ExternalSecret 映射

### PostgreSQL ExternalSecrets

**Namespace**: `postgresql`
**文件**: `argocd/apps/observability/postgresql/overlays/externalsecret.yaml`

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: postgresql-credentials
  namespace: postgresql
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: vault-backend
  target:
    name: detectviz-postgresql-admin
  data:
    - secretKey: postgres-password
      remoteRef:
        key: secret/data/postgresql/admin
        property: postgres-password
```

---

### Keycloak ExternalSecrets

**Namespace**: `keycloak`
**文件**: `argocd/apps/identity/keycloak/base/externalsecret-db.yaml`

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: keycloak-db-creds
  namespace: keycloak
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: vault-backend
  target:
    name: keycloak-db-creds
  data:
    - secretKey: POSTGRES_PASSWORD
      remoteRef:
        key: secret/data/keycloak/database
        property: password
```

---

### Grafana ExternalSecrets

**Namespace**: `grafana`
**文件**:
- `argocd/apps/observability/grafana/overlays/production/externalsecret-admin.yaml`
- `argocd/apps/observability/grafana/overlays/production/externalsecret-db.yaml`
- `argocd/apps/observability/grafana/overlays/production/externalsecret-oauth.yaml`

```yaml
# Admin credentials
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: grafana-admin-creds
  namespace: grafana
spec:
  data:
    - secretKey: admin-user
      remoteRef:
        key: secret/data/grafana/admin
        property: user
```

---

## 安全優勢

| 安全特性 | 實現方式 |
|---------|---------|
| **Zero Trust** | 每個 namespace 只能訪問自己的 secrets |
| **Least Privilege** | Vault policy 限制僅 `read` 和 `list` 權限 |
| **Namespace 隔離** | PostgreSQL、Keycloak、Grafana、Monitoring 完全分離 |
| **Attack Surface 最小化** | 任何單一 Pod 被攻擊不會影響其他 namespace |
| **Audit Trail** | Vault audit log 記錄所有 secret 訪問 |

---

## 手動創建 Vault Secrets

### 1. 初始化 PostgreSQL Secrets

```bash
# PostgreSQL admin credentials
vault kv put secret/postgresql/admin \
  postgres-password="$(openssl rand -base64 32)" \
  app-password="$(openssl rand -base64 32)" \
  repmgr-password="$(openssl rand -base64 32)" \
  postgresUser="postgres" \
  postgresPasswordMd5="md5$(echo -n 'password_here' | md5sum | awk '{print $1}')" \
  appUser="grafana" \
  appPasswordMd5="md5$(echo -n 'password_here' | md5sum | awk '{print $1}')"

# PostgreSQL initdb scripts
vault kv put secret/postgresql/initdb \
  init-grafana-sql="CREATE DATABASE grafana; CREATE USER grafana WITH PASSWORD 'password_here'; GRANT ALL PRIVILEGES ON DATABASE grafana TO grafana;"
```

### 2. 初始化 Keycloak Secrets

```bash
vault kv put secret/keycloak/database \
  password="$(openssl rand -base64 32)"
```

### 3. 初始化 Grafana Secrets

```bash
# Admin credentials
vault kv put secret/grafana/admin \
  user="admin" \
  password="$(openssl rand -base64 32)"

# Database credentials
vault kv put secret/grafana/database \
  user="grafana" \
  password="$(openssl rand -base64 32)"

# OAuth2 client secret
vault kv put secret/grafana/oauth \
  keycloak-client-secret="$(openssl rand -base64 32)"
```

### 4. 初始化 Monitoring Secrets

```bash
vault kv put secret/monitoring/minio \
  root-user="admin" \
  root-password="$(openssl rand -base64 32)" \
  mimir-access-key="mimir" \
  mimir-secret-key="$(openssl rand -base64 32)"
```

---

### Minio ExternalSecrets

**Namespace**: `monitoring`
**文件**: `argocd/apps/observability/minio/overlays/externalsecret.yaml`

```yaml
# Minio root credentials
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: minio-root-credentials
  namespace: monitoring
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: vault-backend
  target:
    name: minio-root-credentials
  data:
    - secretKey: rootUser
      remoteRef:
        key: secret/data/monitoring/minio
        property: root-user
    - secretKey: rootPassword
      remoteRef:
        key: secret/data/monitoring/minio
        property: root-password

---
# Minio user for Mimir
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: minio-mimir-user
  namespace: monitoring
spec:
  data:
    - secretKey: accessKey
      remoteRef:
        key: secret/data/monitoring/minio
        property: mimir-access-key
    - secretKey: secretKey
      remoteRef:
        key: secret/data/monitoring/minio
        property: mimir-secret-key
```

---

## 參考文件

- External Secrets Operator: https://external-secrets.io/
- Vault KV v2: https://developer.hashicorp.com/vault/docs/secrets/kv/kv-v2
- Vault Kubernetes Auth: https://developer.hashicorp.com/vault/docs/auth/kubernetes
- Platform Engineering 最佳實踐: `APP_CONFIG_NOTES.md`

---

**最後更新**: 2025-11-16
**維護者**: DetectViz Platform Team
