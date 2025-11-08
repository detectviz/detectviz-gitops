#!/bin/bash
set -eo pipefail

# ============================================================================
# ArgoCD 安裝腳本
# 用途: 首次安裝 ArgoCD HA 版本到 Kubernetes 叢集
# 版本: 2.0
# ============================================================================

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 配置變數
ARGOCD_VERSION="${ARGOCD_VERSION:-v3.0.20}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
INSTALL_TIMEOUT="${INSTALL_TIMEOUT:-300}"

# 日誌函數
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

error_exit() {
    log_error "$1"
    exit 1
}

# 前置檢查
pre_check() {
    log_info "執行前置檢查..."

    # 檢查 kubectl
    if ! command -v kubectl &> /dev/null; then
        error_exit "kubectl 未安裝"
    fi

    # 檢查叢集連線
    if ! kubectl cluster-info &> /dev/null; then
        error_exit "無法連接到 Kubernetes 叢集"
    fi

    # 檢查節點狀態
    local not_ready=$(kubectl get nodes --no-headers 2>/dev/null | grep -v " Ready " | wc -l | xargs)
    if [ "$not_ready" -gt 0 ]; then
        log_warning "有 $not_ready 個節點未就緒"
    fi

    log_success "前置檢查通過"
}

# 建立 namespace
create_namespace() {
    log_info "建立 $ARGOCD_NAMESPACE namespace..."

    if kubectl get namespace "$ARGOCD_NAMESPACE" &> /dev/null; then
        log_warning "namespace $ARGOCD_NAMESPACE 已存在，跳過建立"
    else
        kubectl create namespace "$ARGOCD_NAMESPACE"
        log_success "namespace $ARGOCD_NAMESPACE 已建立"
    fi
}

# 安裝 ArgoCD
install_argocd() {
    log_info "套用 ArgoCD HA manifests (版本: $ARGOCD_VERSION)..."

    local manifest_url="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/ha/install.yaml"

    if ! kubectl apply -n "$ARGOCD_NAMESPACE" -f "$manifest_url"; then
        error_exit "ArgoCD manifests 套用失敗"
    fi

    log_success "ArgoCD manifests 已套用"
}

# 等待 Pods 就緒
wait_for_pods() {
    log_info "等待 ArgoCD Pods 就緒（最多 ${INSTALL_TIMEOUT}s）..."

    local waited=0
    local check_interval=5

    while [ $waited -lt $INSTALL_TIMEOUT ]; do
        local running=$(kubectl get pods -n "$ARGOCD_NAMESPACE" --no-headers 2>/dev/null | grep -c "Running" 2>/dev/null || echo "0")
        local total=$(kubectl get pods -n "$ARGOCD_NAMESPACE" --no-headers 2>/dev/null | wc -l 2>/dev/null | tr -d ' ' || echo "0")

        # 確保變數是純數字
        running=$(echo "$running" | tr -d -c '0-9' || echo "0")
        total=$(echo "$total" | tr -d -c '0-9' || echo "0")

        if [ "$total" -gt 0 ] 2>/dev/null; then
            echo -ne "\r  Pods 狀態: $running/$total Running (${waited}s)"

            # 檢查核心組件是否就緒
            local server_ready=$(kubectl get pods -n "$ARGOCD_NAMESPACE" -l app.kubernetes.io/name=argocd-server --no-headers 2>/dev/null | grep -c "Running" 2>/dev/null || echo "0")
            local repo_ready=$(kubectl get pods -n "$ARGOCD_NAMESPACE" -l app.kubernetes.io/name=argocd-repo-server --no-headers 2>/dev/null | grep -c "Running" 2>/dev/null || echo "0")
            local controller_ready=$(kubectl get pods -n "$ARGOCD_NAMESPACE" -l app.kubernetes.io/name=argocd-application-controller --no-headers 2>/dev/null | grep -c "Running" 2>/dev/null || echo "0")

            # 確保變數是純數字
            server_ready=$(echo "$server_ready" | tr -d -c '0-9' || echo "0")
            repo_ready=$(echo "$repo_ready" | tr -d -c '0-9' || echo "0")
            controller_ready=$(echo "$controller_ready" | tr -d -c '0-9' || echo "0")

            if [ "$server_ready" -ge 1 ] 2>/dev/null && [ "$repo_ready" -ge 1 ] 2>/dev/null && [ "$controller_ready" -ge 1 ] 2>/dev/null; then
                echo ""
                log_success "ArgoCD 核心組件已就緒"
                return 0
            fi
        fi

        sleep $check_interval
        waited=$((waited + check_interval))
    done

    echo ""
    log_warning "等待超時，但安裝可能仍在進行中"
}

# 驗證安裝
verify_installation() {
    log_info "驗證 ArgoCD 安裝..."

    # 檢查 Deployment
    local deployments=$(kubectl get deployment -n "$ARGOCD_NAMESPACE" --no-headers 2>/dev/null | wc -l | xargs)
    log_info "  Deployments: $deployments"

    # 檢查 StatefulSet
    local statefulsets=$(kubectl get statefulset -n "$ARGOCD_NAMESPACE" --no-headers 2>/dev/null | wc -l | xargs)
    log_info "  StatefulSets: $statefulsets"

    # 檢查 Service
    local services=$(kubectl get service -n "$ARGOCD_NAMESPACE" --no-headers 2>/dev/null | wc -l | xargs)
    log_info "  Services: $services"

    # 顯示 Pod 狀態
    echo ""
    kubectl get pods -n "$ARGOCD_NAMESPACE"
    echo ""

    log_success "ArgoCD 安裝驗證完成"
}

# 顯示後續步驟
show_next_steps() {
    echo ""
    echo "=========================================="
    log_success "✅ ArgoCD 安裝完成！"
    echo "=========================================="
    echo ""
    log_info "後續步驟："
    echo ""
    echo "  1. 取得初始管理員密碼："
    echo "     kubectl -n $ARGOCD_NAMESPACE get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo"
    echo ""
    echo "  2. Port-forward 到 ArgoCD Server："
    echo "     kubectl port-forward svc/argocd-server -n $ARGOCD_NAMESPACE 8080:443"
    echo ""
    echo "  3. 瀏覽器訪問："
    echo "     https://localhost:8080"
    echo ""
    echo "  4. 登入憑證："
    echo "     使用者名稱: admin"
    echo "     密碼: (執行步驟 1 取得)"
    echo ""
}

# 主函數
main() {
    echo "=========================================="
    echo "  ArgoCD HA 安裝腳本"
    echo "=========================================="
    echo ""
    log_info "版本: $ARGOCD_VERSION"
    log_info "Namespace: $ARGOCD_NAMESPACE"
    echo ""

    pre_check
    echo ""

    create_namespace
    echo ""

    install_argocd
    echo ""

    wait_for_pods
    echo ""

    verify_installation

    show_next_steps
}

# 執行主函數
main "$@"