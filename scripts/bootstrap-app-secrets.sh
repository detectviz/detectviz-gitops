#!/bin/bash
#!/bin/bash
# ==========================================
# ⚠️ DEPRECATION NOTICE ⚠️
# ==========================================
# 
# 此腳本僅用於開發/測試環境！
# 
# 生產環境請使用 Vault + External Secrets Operator:
#   ./scripts/vault-setup-observability.sh
#
# 參考文檔:
#   docs/infrastructure/05-argocd/deployment/vault-secrets-setup.md
#
# ==========================================

set -euo pipefail

echo "=========================================="
echo "⚠️  DEPRECATION WARNING"
echo "=========================================="
echo ""
echo "此腳本僅用於開發/測試環境！"
echo "生產環境請使用 Vault + External Secrets Operator。"
echo ""
echo "新的推薦方式:"
echo "  ./scripts/vault-setup-observability.sh"
echo ""
echo "參考文檔:"
echo "  docs/infrastructure/05-argocd/deployment/vault-secrets-setup.md"
echo ""
read -p "確認要繼續使用此腳本? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "操作已取消"
    exit 0
fi
echo ""

# DetectViz 應用 Secrets 初始化腳本
# 用於在部署應用前生成必要的 Kubernetes Secrets
#
# 使用方法:
#   ./scripts/bootstrap-app-secrets.sh
#
# 注意:
#   - 執行前請確保已連接到正確的 Kubernetes 集群
#   - 密碼會自動生成,也可以通過環境變數指定
#   - Secrets 創建成功後會輸出到控制台

set -euo pipefail

# 顏色輸出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 輔助函數
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 生成隨機密碼
generate_password() {
    local length=${1:-32}
    openssl rand -base64 $length | tr -d "=+/" | cut -c1-$length
}

# 檢查 Secret 是否存在
secret_exists() {
    local namespace=$1
    local secret_name=$2
    kubectl get secret "$secret_name" -n "$namespace" &>/dev/null
}

# ============================================
# 1. PostgreSQL Secrets
# ============================================
create_postgresql_secrets() {
    log_info "創建 PostgreSQL Secrets..."
    
    local namespace="postgresql"
    
    # 創建命名空間(如果不存在)
    kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -
    
    # 1.1 detectviz-postgresql-admin
    if secret_exists "$namespace" "detectviz-postgresql-admin"; then
        log_warn "Secret detectviz-postgresql-admin 已存在,跳過創建"
    else
        local postgres_password=${POSTGRES_ADMIN_PASSWORD:-$(generate_password 32)}
        local app_password=${POSTGRES_APP_PASSWORD:-$(generate_password 32)}
        local repmgr_password=${POSTGRES_REPMGR_PASSWORD:-$(generate_password 32)}
        
        kubectl create secret generic detectviz-postgresql-admin \
            -n "$namespace" \
            --from-literal=postgres-password="$postgres_password" \
            --from-literal=password="$app_password" \
            --from-literal=repmgr-password="$repmgr_password"
        
        log_info "✅ Created detectviz-postgresql-admin"
        log_info "  - postgres-password: $postgres_password"
        log_info "  - password: $app_password"
        log_info "  - repmgr-password: $repmgr_password"
    fi
    
    # 1.2 detectviz-pgpool-users
    if secret_exists "$namespace" "detectviz-pgpool-users"; then
        log_warn "Secret detectviz-pgpool-users 已存在,跳過創建"
    else
        # 生成 pgpool_passwd 文件內容
        local app_password=$(kubectl get secret detectviz-postgresql-admin -n "$namespace" -o jsonpath='{.data.password}' | base64 -d)
        local pgpool_passwd="postgres:$(echo -n "$app_password" | md5sum | cut -d' ' -f1)"
        
        kubectl create secret generic detectviz-pgpool-users \
            -n "$namespace" \
            --from-literal=pgpool_passwd="$pgpool_passwd"
        
        log_info "✅ Created detectviz-pgpool-users"
    fi
    
    # 1.3 detectviz-postgresql-initdb
    if secret_exists "$namespace" "detectviz-postgresql-initdb"; then
        log_warn "Secret detectviz-postgresql-initdb 已存在,跳過創建"
    else
        local grafana_password=${GRAFANA_DB_PASSWORD:-$(generate_password 32)}
        
        cat > /tmp/initdb.sql <<EOF
-- 創建 Grafana 資料庫
CREATE DATABASE grafana OWNER postgres ENCODING 'UTF8';

-- 創建 Grafana 使用者
CREATE USER grafana WITH PASSWORD '$grafana_password';

-- 授予權限
GRANT ALL PRIVILEGES ON DATABASE grafana TO grafana;
ALTER DATABASE grafana OWNER TO grafana;
EOF
        
        kubectl create secret generic detectviz-postgresql-initdb \
            -n "$namespace" \
            --from-file=initdb.sql=/tmp/initdb.sql
        
        rm /tmp/initdb.sql
        
        log_info "✅ Created detectviz-postgresql-initdb"
        log_info "  - grafana password: $grafana_password"
        
        # 保存 Grafana 密碼供後續使用
        export GRAFANA_DB_PASSWORD="$grafana_password"
    fi
}

# ============================================
# 2. Grafana Secrets
# ============================================
create_grafana_secrets() {
    log_info "創建 Grafana Secrets..."
    
    local namespace="grafana"
    
    # 創建命名空間(如果不存在)
    kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -
    
    # 2.1 grafana-admin
    if secret_exists "$namespace" "grafana-admin"; then
        log_warn "Secret grafana-admin 已存在,跳過創建"
    else
        local admin_user="admin"
        local admin_password=${GRAFANA_ADMIN_PASSWORD:-$(generate_password 24)}
        
        kubectl create secret generic grafana-admin \
            -n "$namespace" \
            --from-literal=admin-user="$admin_user" \
            --from-literal=admin-password="$admin_password"
        
        log_info "✅ Created grafana-admin"
        log_info "  - admin-user: $admin_user"
        log_info "  - admin-password: $admin_password"
    fi
    
    # 2.2 grafana-database
    if secret_exists "$namespace" "grafana-database"; then
        log_warn "Secret grafana-database 已存在,跳過創建"
    else
        # 從 PostgreSQL initdb secret 獲取密碼,或使用環境變數
        if [ -z "${GRAFANA_DB_PASSWORD:-}" ]; then
            log_error "GRAFANA_DB_PASSWORD 未設置,請先創建 PostgreSQL secrets"
            return 1
        fi
        
        kubectl create secret generic grafana-database \
            -n "$namespace" \
            --from-literal=GF_DATABASE_TYPE=postgres \
            --from-literal=GF_DATABASE_HOST=postgresql-pgpool.postgresql.svc.cluster.local:5432 \
            --from-literal=GF_DATABASE_NAME=grafana \
            --from-literal=GF_DATABASE_USER=grafana \
            --from-literal=GF_DATABASE_PASSWORD="$GRAFANA_DB_PASSWORD" \
            --from-literal=GF_DATABASE_SSL_MODE=disable
        
        log_info "✅ Created grafana-database"
    fi
}

# ============================================
# 3. Keycloak Secrets (可選)
# ============================================
create_keycloak_secrets() {
    log_info "創建 Keycloak Secrets..."
    
    local namespace="keycloak"
    
    # 創建命名空間(如果不存在)
    kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -
    
    # 3.1 keycloak-admin
    if secret_exists "$namespace" "keycloak-admin"; then
        log_warn "Secret keycloak-admin 已存在,跳過創建"
    else
        local admin_user="admin"
        local admin_password=${KEYCLOAK_ADMIN_PASSWORD:-$(generate_password 24)}
        
        kubectl create secret generic keycloak-admin \
            -n "$namespace" \
            --from-literal=admin-user="$admin_user" \
            --from-literal=admin-password="$admin_password"
        
        log_info "✅ Created keycloak-admin"
        log_info "  - admin-user: $admin_user"
        log_info "  - admin-password: $admin_password"
    fi
    
    # 3.2 keycloak-database (使用 PostgreSQL)
    if secret_exists "$namespace" "keycloak-database"; then
        log_warn "Secret keycloak-database 已存在,跳過創建"
    else
        local db_password=${KEYCLOAK_DB_PASSWORD:-$(generate_password 32)}
        
        kubectl create secret generic keycloak-database \
            -n "$namespace" \
            --from-literal=password="$db_password"
        
        log_info "✅ Created keycloak-database"
        log_info "  - password: $db_password"
    fi
}

# ============================================
# 主程序
# ============================================
main() {
    log_info "=========================================="
    log_info "DetectViz 應用 Secrets 初始化"
    log_info "=========================================="
    log_info ""
    
    # 檢查 kubectl 連接
    if ! kubectl cluster-info &>/dev/null; then
        log_error "無法連接到 Kubernetes 集群,請檢查 kubeconfig"
        exit 1
    fi
    
    log_info "當前集群: $(kubectl config current-context)"
    log_info ""
    
    # 詢問是否繼續
    read -p "確認要在此集群上創建 Secrets? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warn "操作已取消"
        exit 0
    fi
    
    log_info ""
    
    # 創建所有 Secrets
    create_postgresql_secrets
    log_info ""
    
    create_grafana_secrets
    log_info ""
    
    create_minio_secrets
    log_info ""
    
    create_grafana_oauth_secret
    log_info ""
    
    # Keycloak 是可選的
    read -p "是否創建 Keycloak Secrets? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        create_keycloak_secrets
        log_info ""
    fi
    
    log_info "=========================================="
    log_info "✅ Secrets 初始化完成!"
    log_info "=========================================="
    log_info ""
    log_info "下一步:"
    log_info "  1. 驗證 Secrets: kubectl get secrets -n postgresql"
    log_info "  2. 部署應用: kubectl argo app sync <app-name>"
    log_info ""
    log_warn "重要: 請妥善保存生成的密碼!"
}

# 執行主程序
main "$@"

# ============================================
# 4. Minio Secrets (必須)
# ============================================
create_minio_secrets() {
    log_info "創建 Minio Secrets..."
    
    local namespace="monitoring"
    
    # 確保命名空間存在
    kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -
    
    # 4.1 minio-root-credentials
    if secret_exists "$namespace" "minio-root-credentials"; then
        log_warn "Secret minio-root-credentials 已存在,跳過創建"
    else
        local root_user="admin"
        local root_password=${MINIO_ROOT_PASSWORD:-$(generate_password 32)}
        
        kubectl create secret generic minio-root-credentials \
            -n "$namespace" \
            --from-literal=rootUser="$root_user" \
            --from-literal=rootPassword="$root_password"
        
        log_info "✅ Created minio-root-credentials"
        log_info "  - rootUser: $root_user"
        log_info "  - rootPassword: $root_password"
    fi
    
    # 4.2 minio-mimir-user (Mimir 專用使用者)
    if secret_exists "$namespace" "minio-mimir-user"; then
        log_warn "Secret minio-mimir-user 已存在,跳過創建"
    else
        local access_key="mimir"
        local secret_key=${MINIO_MIMIR_SECRET_KEY:-$(generate_password 40)}
        
        kubectl create secret generic minio-mimir-user \
            -n "$namespace" \
            --from-literal=accessKey="$access_key" \
            --from-literal=secretKey="$secret_key"
        
        log_info "✅ Created minio-mimir-user"
        log_info "  - accessKey: $access_key"
        log_info "  - secretKey: $secret_key"
    fi
}

# ============================================
# 5. Grafana Keycloak OAuth Secret (可選)
# ============================================
create_grafana_oauth_secret() {
    log_info "創建 Grafana Keycloak OAuth Secret..."
    
    local namespace="monitoring"
    
    # 5.1 grafana-keycloak-oauth
    if secret_exists "$namespace" "grafana-keycloak-oauth"; then
        log_warn "Secret grafana-keycloak-oauth 已存在,跳過創建"
    else
        local client_secret=${GRAFANA_KEYCLOAK_CLIENT_SECRET:-$(generate_password 32)}
        
        kubectl create secret generic grafana-keycloak-oauth \
            -n "$namespace" \
            --from-literal=client-secret="$client_secret"
        
        log_info "✅ Created grafana-keycloak-oauth"
        log_info "  - client-secret: $client_secret"
        log_warn "⚠️  請在 Keycloak 中創建 'grafana' client 並使用此 secret: $client_secret"
    fi
}
