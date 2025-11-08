#!/bin/bash
set -e

# DetectViz Platform - ArgoCD SSH 認證設置腳本
# 安全設置 ArgoCD 的 SSH 倉庫認證，避免將私鑰存放在公開倉庫中

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 顏色代碼
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 檢查必要的工具
check_dependencies() {
    log_info "檢查必要的工具..."

    if ! command -v kubectl >/dev/null 2>&1; then
        log_error "kubectl 未安裝或不在 PATH 中"
        exit 1
    fi

    if ! kubectl cluster-info >/dev/null 2>&1; then
        log_error "無法連接到 Kubernetes 集群"
        exit 1
    fi

    log_success "依賴檢查通過"
}

# 檢查 SSH 金鑰文件
check_ssh_key() {
    local ssh_key_path="${SSH_KEY_PATH:-$HOME/.ssh/id_ed25519_detectviz}"

    log_info "檢查 SSH 金鑰文件: $ssh_key_path"

    if [ ! -f "$ssh_key_path" ]; then
        log_error "SSH 金鑰文件不存在: $ssh_key_path"
        log_info "請確保 SSH 金鑰存在，或設置 SSH_KEY_PATH 環境變數"
        log_info "示例: export SSH_KEY_PATH=/path/to/your/ssh/key"
        exit 1
    fi

    if [ ! -r "$ssh_key_path" ]; then
        log_error "無法讀取 SSH 金鑰文件: $ssh_key_path"
        exit 1
    fi

    log_success "SSH 金鑰文件存在且可讀取"
    echo "$ssh_key_path"
}

# 設置 ArgoCD SSH 認證
setup_argocd_ssh() {
    local ssh_key_path="$1"

    log_info "設置 ArgoCD SSH 認證..."

    # 創建包含 SSH 私鑰的 secret
    log_info "創建 ArgoCD SSH 認證 secret..."

    # 將私鑰讀取並 base64 編碼
    local private_key_b64
    private_key_b64=$(base64 -w 0 < "$ssh_key_path")

    # 創建或更新 secret
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: detectviz-github-ssh-creds
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repo-creds
stringData:
  url: git@github.com:detectviz
  type: git
  sshPrivateKey: |
$(sed 's/^/    /' "$ssh_key_path")
EOF

    log_success "ArgoCD SSH 認證 secret 已創建/更新"

    # 驗證 secret
    log_info "驗證 SSH 認證 secret..."
    if kubectl get secret detectviz-github-ssh-creds -n argocd >/dev/null 2>&1; then
        log_success "SSH 認證 secret 驗證成功"
    else
        log_error "SSH 認證 secret 創建失敗"
        exit 1
    fi
}

# 測試 SSH 認證
test_ssh_auth() {
    log_info "測試 SSH 認證..."

    # 等待 ArgoCD repo-server 應用配置
    log_info "等待 ArgoCD repo-server 重啟以應用新配置..."
    kubectl rollout status deployment/argocd-repo-server -n argocd --timeout=60s

    # 測試倉庫訪問（如果可能的話）
    log_info "SSH 認證設置完成"
    log_info "您可以通過以下方式測試："
    log_info "  kubectl get applications -n argocd"
    log_info "  kubectl describe application <app-name> -n argocd"
}

# 主函數
main() {
    echo "=========================================="
    echo "DetectViz Platform - ArgoCD SSH 認證設置"
    echo "=========================================="

    check_dependencies

    local ssh_key_path
    ssh_key_path=$(check_ssh_key)

    setup_argocd_ssh "$ssh_key_path"

    test_ssh_auth

    echo ""
    echo "=========================================="
    echo "✅ ArgoCD SSH 認證設置完成"
    echo "=========================================="
    echo ""
    echo "安全提醒："
    echo "- SSH 私鑰已安全存儲在 Kubernetes secret 中"
    echo "- 私鑰不會明碼存放在 Git 倉庫中"
    echo "- 確保只有授權人員能訪問集群"
    echo ""
    echo "後續步驟："
    echo "1. 檢查 ArgoCD 應用同步狀態"
    echo "2. 如果仍有認證問題，請檢查 SSH 金鑰權限"
}

# 腳本入口
main "$@"
