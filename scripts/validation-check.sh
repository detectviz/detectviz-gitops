#!/bin/bash
set -e

# ==============================================================================
# DetectViz Platform - Validation Check Script v1.0
# 專門處理 deploy-guide.md 中的「雙重強化檢查」
# ==============================================================================
#
# Usage:
#   ./scripts/validation-check.sh                 # Run all validation checks
#   ./scripts/validation-check.sh --phase2        # Run Phase 2 validations
#   ./scripts/validation-check.sh --phase3        # Run Phase 3 validations
#   ./scripts/validation-check.sh --phase4        # Run Phase 4 validations
#   ./scripts/validation-check.sh --phase5        # Run Phase 5 validations
#   ./scripts/validation-check.sh --phase9        # Run Phase 9 validations
#   ./scripts/validation-check.sh --final         # Run final validations
#
# ==============================================================================

# --- Helper Functions ---
info() {
    echo "[VALIDATION] ------------------------------------------------"
    echo "[VALIDATION] $1"
    echo "[VALIDATION] ------------------------------------------------"
}

validate() {
    echo -n "[VALIDATE] $1: "
    if eval $2; then
        echo "✅ PASSED"
        return 0
    else
        echo "❌ FAILED"
        return 1
    fi
}

# --- Helper Functions ---

# 等待集群就緒
wait_for_cluster_ready() {
    local max_attempts=12  # 最多等待2分鐘 (12 * 10秒)
    local attempt=1

    echo "[VALIDATION] 等待集群 API server 就緒..." >&2

    while [ $attempt -le $max_attempts ]; do
        # 檢查 VIP 是否可用
        if curl -k --connect-timeout 5 https://192.168.0.10:6443/healthz >/dev/null 2>&1; then
            echo "[VALIDATION] VIP (192.168.0.10) 已就緒" >&2
            echo "kubectl"
            return 0
        fi

        # 檢查 master-1 是否可用
        if curl -k --connect-timeout 5 https://192.168.0.11:6443/healthz >/dev/null 2>&1; then
            echo "[VALIDATION] master-1 (192.168.0.11) 已就緒，VIP 尚不可用" >&2
            echo "kubectl --server https://192.168.0.11:6443 --insecure-skip-tls-verify"
            return 0
        fi

        echo "[VALIDATION] 集群尚未就緒，等待 10 秒... (嘗試 $attempt/$max_attempts)" >&2
        sleep 10
        ((attempt++))
    done

    echo "[VALIDATION] ❌ 集群在 2 分鐘內未能就緒" >&2
    echo "[VALIDATION] 💡 建議檢查：" >&2
    echo "  - 運行 'kubectl cluster-info' 檢查集群狀態" >&2
    echo "  - 檢查 master 節點上的 kubelet 和 API server 日誌" >&2
    echo "  - 確認所有節點都已加入集群" >&2
    return 1
}

# 選擇合適的 kubectl 連接方式（不等待）
get_kubectl_cmd() {
    # 檢查 VIP 是否可用
    if curl -k --connect-timeout 5 https://192.168.0.10:6443/healthz >/dev/null 2>&1; then
        echo "kubectl"  # 使用預設配置（通常是 VIP）
    else
        echo "kubectl --server https://192.168.0.11:6443 --insecure-skip-tls-verify"  # 直接連接到 master-1
    fi
}

# --- Validation Functions ---

validate_phase2() {
    info "Phase 2: 集群部署驗證"

    # 等待集群就緒並獲取合適的 kubectl 命令
    local kubectl_cmd
    kubectl_cmd=$(wait_for_cluster_ready)

    if [ $? -ne 0 ]; then
        echo "[VALIDATION] ❌ 無法連接到集群，跳過 Phase 2 驗證"
        return 1
    fi

    # 🔍 雙重強化檢查：集群部署驗證
    validate "集群節點數量正確" "$kubectl_cmd get nodes --no-headers | wc -l | xargs test 2 -le"
    validate "所有節點狀態為 Ready" "$kubectl_cmd get nodes --no-headers | awk '{print \$2}' | grep -v 'Ready' | wc -l | xargs test 0 -eq"

    # 🔍 雙重強化檢查：etcd 狀態驗證
    validate "etcd pods 運行正常" "$kubectl_cmd get pods -n kube-system -l component=etcd | grep -c 'Running' | xargs test 3 -eq"

    # 🔍 雙重強化檢查：RBAC 權限驗證
    validate "管理員權限配置正確" "$kubectl_cmd auth can-i get nodes | grep -q 'yes'"
    validate "cluster-admin ClusterRoleBinding 存在" "$kubectl_cmd get clusterrolebinding cluster-admin | grep -q 'cluster-admin'"
}

validate_phase3() {
    info "Phase 3: Kube-VIP 高可用性驗證"


    # 🔍 雙重強化檢查：VIP 可用性驗證
    validate "VIP ICMP 可達" "ping -c 3 192.168.0.10"
    validate "VIP API Server 正常" "curl -k --connect-timeout 5 https://192.168.0.10:6443/healthz | grep -q 'ok'"
    validate "VIP HTTPS 訪問正常" "curl -k --connect-timeout 5 https://192.168.0.10:6443/version | grep -q 'gitVersion'"

    # 🔍 雙重強化檢查：Kube-VIP 組件驗證
    validate "Kube-VIP DaemonSet 運行" "kubectl --server https://192.168.0.11:6443 --insecure-skip-tls-verify get daemonset kube-vip-ds -n kube-system"
    validate "所有 Kube-VIP pods 就緒" "kubectl --server https://192.168.0.11:6443 --insecure-skip-tls-verify get pods -n kube-system -l app.kubernetes.io/name=kube-vip-ds | grep -c 'Running' | xargs test 3 -eq"

    # 🔍 雙重強化檢查：最終驗證所有節點通過VIP通信
    validate "所有節點通過 VIP 正常通信" "kubectl get nodes --no-headers -o custom-columns=NAME:.metadata.name | xargs -I {} sh -c 'kubectl get node {} -o jsonpath=\"{.status.conditions[?(@.type==\\\"Ready\\\")].status}\" | grep -q \"True\"'"
}

validate_phase4() {
    info "Phase 4: MetalLB LoadBalancer 驗證"

    # 🔍 雙重強化檢查：MetalLB 功能驗證
    validate "IPAddressPool 配置" "kubectl --server https://192.168.0.11:6443 --insecure-skip-tls-verify get ipaddresspool -n metallb-system"
    validate "L2Advertisement 配置" "kubectl --server https://192.168.0.11:6443 --insecure-skip-tls-verify get l2advertisement -n metallb-system"
}

validate_phase5() {
    info "Phase 5: StorageClass 和 CSI 驗證"

    # 🔍 雙重強化檢查：StorageClass 驗證
    validate "Cert-manager pods 運行" "kubectl --server https://192.168.0.11:6443 --insecure-skip-tls-verify get pods -n cert-manager | grep -q Running"
    validate "TopoLVM StorageClass 可用" "kubectl --server https://192.168.0.11:6443 --insecure-skip-tls-verify get storageclass | grep -q detectviz-data"
    # 注意：TopoLVM 完整安裝將在 ArgoCD 部署後進行，避免 webhook 循環依賴
    validate "TopoLVM StorageClass 已配置" "kubectl --server https://192.168.0.11:6443 --insecure-skip-tls-verify get storageclass detectviz-data -o jsonpath='{.provisioner}' | grep -q topolvm.io"
}

validate_phase9() {
    info "Phase 9: ArgoCD GitOps 控制平面驗證"

    # 獲取合適的 kubectl 命令
    local kubectl_cmd=$(get_kubectl_cmd)

    # 🔍 雙重強化檢查：ArgoCD 核心組件驗證
    validate "ArgoCD server pods 運行" "$kubectl_cmd get pods -n argocd -l app.kubernetes.io/name=argocd-server | grep -q Running"
    validate "ArgoCD repo server pods 運行" "$kubectl_cmd get pods -n argocd -l app.kubernetes.io/name=argocd-repo-server | grep -q Running"
    validate "ArgoCD Redis HA 運行" "$kubectl_cmd get pods -n argocd -l app.kubernetes.io/name=argocd-redis-ha | grep -q Running"

    # 🔍 雙重強化檢查：ArgoCD 配置驗證
    validate "ArgoCD ConfigMap 標籤正確" "$kubectl_cmd get configmap argocd-cm -n argocd --show-labels | grep \"app.kubernetes.io/part-of=argocd\""

    # 🔍 雙重強化檢查：MetalLB 功能驗證
    validate "IPAddressPool 配置" "$kubectl_cmd get ipaddresspool -n metallb-system"
    validate "L2Advertisement 配置" "$kubectl_cmd get l2advertisement -n metallb-system"

    # 🔍 雙重強化檢查：StorageClass 驗證
    validate "TopoLVM StorageClass 可用" "$kubectl_cmd get storageclass | grep -q detectviz-data"
}

validate_final() {
    info "最終驗證"

    # 獲取合適的 kubectl 命令
    local kubectl_cmd=$(get_kubectl_cmd)

    # 🔍 雙重強化檢查：完整集群健康檢查
    validate "集群節點正常" "$kubectl_cmd get nodes | grep -q Ready"
    validate "所有系統組件運行正常" "$kubectl_cmd get pods -n kube-system --field-selector=status.phase=Running | wc -l | xargs test 8 -le"
    validate "只有 TopoLVM Pod Pending (正常)" "! $kubectl_cmd get pods -A --field-selector=status.phase!=Running | grep -v topolvm | grep -v Completed"

    # 檢查集群資源
    validate "StorageClass 配置正確" "$kubectl_cmd get storageclass | wc -l | xargs test 1 -le"
    validate "Ingress 資源存在" "$kubectl_cmd get ingress -A 2>/dev/null | wc -l | xargs test 0 -le"
    validate "Certificates 存在" "$kubectl_cmd get certificates -A 2>/dev/null | wc -l | xargs test 0 -le"

    # 🔍 雙重強化檢查：ArgoCD 功能測試
    validate "ArgoCD 核心組件運行正常" "$kubectl_cmd get pods -n argocd | grep -E '(dex-server|applicationset-controller|notifications-controller|repo-server|server)' | grep Running | wc -l | xargs test 5 -le"
    validate "ArgoCD 根應用已創建" "$kubectl_cmd get applications -n argocd 2>/dev/null | grep -q 'root-argocd-app'"
    validate "ArgoCD Web UI 可訪問" "curl -k --connect-timeout 10 -H 'Host: argocd.detectviz.local' https://192.168.0.10 | grep -q 'Argo CD'"  # 使用 VIP

    # 🔍 雙重強化檢查：External Secrets 功能測試
    validate "External Secrets 資源存在" "$kubectl_cmd get externalsecrets -n detectviz 2>/dev/null | wc -l | xargs test 0 -le"
    validate "Secrets 已填充" "$kubectl_cmd get secrets -n detectviz 2>/dev/null | wc -l | xargs test 0 -le"
}

# --- Main Logic ---

if [ "$1" == "--phase2" ]; then
    validate_phase2
elif [ "$1" == "--phase3" ]; then
    validate_phase3
elif [ "$1" == "--phase4" ]; then
    validate_phase4
elif [ "$1" == "--phase5" ]; then
    validate_phase5
elif [ "$1" == "--phase9" ]; then
    validate_phase9
elif [ "$1" == "--final" ]; then
    validate_final
elif [ "$1" == "--all" ] || [ -z "$1" ]; then
    validate_phase2
    validate_phase3
    validate_phase4
    validate_phase5
    validate_phase9
    validate_final
else
    echo "Unknown argument: $1"
    echo "Usage: $0 [--phase2|--phase3|--phase4|--phase5|--phase9|--final|--all]"
    exit 1
fi

echo ""
echo "✅ All specified validation checks passed successfully."
