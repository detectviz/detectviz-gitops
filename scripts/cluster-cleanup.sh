#!/bin/bash
set -e

# DetectViz Platform - Cluster Cleanup and Recovery Script
# 用於清理和修復 Kubernetes 集群的各種問題

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 顏色代碼
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 幫助函數
show_help() {
    cat << EOF
DetectViz Platform - 集群清理與修復腳本

用法: $0 [選項] [動作]

選項:
    -h, --help          顯示此幫助訊息
    -i, --inventory     指定 Ansible inventory 檔案 (預設: ../ansible/inventory.ini)
    -v, --verbose       詳細輸出

動作:
    check-etcd          檢查 etcd 是否有舊集群狀態殘留
    cleanup-etcd        清理 etcd 舊集群狀態和數據
    reset-cluster       完全重置集群 (kubeadm reset + 清理)
    fix-ssh-keys        清除 SSH known_hosts 記錄
    manual-ha-fix       手動修復 HA 集群部署失敗
    network-cleanup     清理網路配置殘留
    full-recovery       執行完整的集群修復流程

範例:
    $0 check-etcd                    # 檢查 etcd 狀態
    $0 cleanup-etcd                  # 清理 etcd 數據
    $0 reset-cluster                 # 完全重置集群
    $0 full-recovery                 # 完整修復流程

EOF
}

# 日誌函數
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# 預設值
INVENTORY="${PROJECT_ROOT}/ansible/inventory.ini"
VERBOSE=false

# 解析命令行參數
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -i|--inventory)
            INVENTORY="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        *)
            ACTION="$1"
            shift
            break
            ;;
    esac
done

# 檢查 inventory 檔案
if [[ ! -f "$INVENTORY" ]]; then
    log_error "找不到 Ansible inventory 檔案: $INVENTORY"
    exit 1
fi

# Ansible 命令包裝
ansible_cmd() {
    local host="$1"
    local module="${2:-shell}"
    local args="$3"
    local become="${4:--b}"

    # 使用正確的 ansible.cfg 和 inventory
    local ansible_config="$PROJECT_ROOT/ansible/ansible.cfg"

    if [[ "$VERBOSE" == "true" ]]; then
        ANSIBLE_CONFIG="$ansible_config" ansible "$host" -i "$INVENTORY" -m "$module" -a "$args" $become -v
    else
        ANSIBLE_CONFIG="$ansible_config" ansible "$host" -i "$INVENTORY" -m "$module" -a "$args" $become
    fi
}

# 檢查 etcd 是否有舊集群狀態
check_etcd_status() {
    log_info "檢查 etcd 是否有舊集群狀態殘留..."

    local result
    result=$(ansible_cmd "master-1" "shell" "sudo journalctl -u etcd -n 10 2>/dev/null | grep -c 'peer 192.168.0.12:2380\|peer 192.168.0.13:2380' || true")

    if [[ "$result" =~ "1" ]] || [[ "$result" =~ "2" ]]; then
        log_warn "檢測到 etcd 舊集群狀態，需要緊急清理"
        return 1
    else
        log_success "etcd 狀態正常"
        return 0
    fi
}

# 清理 etcd 數據
cleanup_etcd() {
    log_info "清理 etcd 舊集群狀態和數據..."

    # 停止 kubelet
    log_info "停止 kubelet 服務..."
    ansible_cmd "master-1" "shell" "sudo systemctl stop kubelet" || true

    # 終止 etcd 進程
    log_info "終止 etcd 進程..."
    ansible_cmd "master-1" "shell" "sudo pkill -f etcd && sleep 5" || true

    # 備份並清理 etcd 數據目錄
    log_info "備份並清理 etcd 數據目錄..."
    ansible_cmd "master-1" "shell" "sudo mv /var/lib/etcd /var/lib/etcd-backup-\$(date +%s) 2>/dev/null || true"
    ansible_cmd "master-1" "shell" "sudo rm -rf /var/lib/etcd/* && sudo mkdir -p /var/lib/etcd"

    log_success "etcd 清理完成"
}

# 完全重置集群
reset_cluster() {
    log_info "執行完全集群重置..."

    # 首先嘗試清理 Kubernetes 資源（如果集群還在運行）
    log_info "嘗試清理現有的 Kubernetes 資源..."
    cleanup_k8s_resources_if_possible

    # 重置所有節點
    log_info "重置所有節點的 Kubernetes 配置..."
    ansible_cmd "all" "shell" "sudo kubeadm reset --force" || true

    # 清理 Kubernetes 目錄
    log_info "清理 Kubernetes 配置文件和數據..."
    ansible_cmd "all" "shell" "sudo rm -rf /etc/kubernetes /var/lib/kubelet /var/lib/etcd /etc/cni/net.d /var/run/kubernetes /var/lib/cni"

    # 重啟 containerd
    log_info "重啟 containerd 服務..."
    ansible_cmd "all" "shell" "sudo systemctl restart containerd"

    log_success "集群重置完成"
}

# 清理 Kubernetes 資源（如果集群還在運行）
cleanup_k8s_resources_if_possible() {
    log_info "檢查是否可以清理 Kubernetes 資源..."

    # 只在第一個 master 節點檢查 kubeconfig
    local check_result
    check_result=$(ansible_cmd "masters[0]" "shell" "test -f /etc/kubernetes/admin.conf && echo 'exists' || echo 'not_exists'")

    if [[ "$check_result" =~ "exists" ]]; then
        log_info "檢測到 kubeconfig，嘗試清理集群資源..."
        # 注意：這裡使用 ignore_errors，因為集群可能處於不穩定狀態
        ansible_cmd "masters[0]" "shell" "KUBECONFIG=/etc/kubernetes/admin.conf kubectl delete storageclass --all --ignore-not-found=true --timeout=30s" || true
        ansible_cmd "masters[0]" "shell" "KUBECONFIG=/etc/kubernetes/admin.conf kubectl delete pv --all --ignore-not-found=true --timeout=30s" || true
        ansible_cmd "masters[0]" "shell" "KUBECONFIG=/etc/kubernetes/admin.conf kubectl delete pvc --all --all-namespaces --ignore-not-found=true --timeout=30s" || true
        log_success "Kubernetes 資源清理完成（如果集群在運行）"
    else
        log_info "未檢測到 kubeconfig，跳過 Kubernetes 資源清理"
    fi
}

# 清除 SSH known_hosts
fix_ssh_keys() {
    log_info "清除 SSH known_hosts 記錄..."

    local ips=("192.168.0.11" "192.168.0.12" "192.168.0.13" "192.168.0.14")

    for ip in "${ips[@]}"; do
        log_info "清除 $ip 的 SSH 記錄..."
        # 清理 known_hosts
        ssh-keygen -f ~/.ssh/known_hosts -R "$ip" 2>/dev/null || true
        # 清理 hash known_hosts (如果存在)
        ssh-keygen -f ~/.ssh/known_hosts -R "$ip" -H 2>/dev/null || true
    done

    # 清理可能的 SSH 控制套接字
    log_info "清理 SSH 控制套接字..."
    rm -rf ~/.ssh/master-* 2>/dev/null || true

    # 測試 SSH 連接以重新添加金鑰
    log_info "測試 SSH 連接並重新添加主機金鑰..."
    for ip in "${ips[@]}"; do
        log_info "測試連接 $ip..."
        # 使用 StrictHostKeyChecking=no 臨時允許連接並添加金鑰
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes ubuntu@"$ip" "echo 'SSH 連接測試成功'" 2>/dev/null || log_warn "無法連接到 $ip，可能節點尚未啟動"
    done

    log_success "SSH known_hosts 清理和重新添加完成"
}

# 手動修復 HA 集群
manual_ha_fix() {
    log_info "執行手動 HA 集群修復..."

    # 清除 SSH 記錄
    fix_ssh_keys

    # 在 master-1 上上傳控制平面證書
    log_info "在 master-1 上上傳控制平面證書..."
    ssh ubuntu@192.168.0.11 "sudo kubeadm init phase upload-certs --upload-certs"

    # 生成 join 命令和證書金鑰
    log_info "生成 join 命令和證書金鑰..."
    local join_cmd
    local cert_key

    join_cmd=$(ssh ubuntu@192.168.0.11 "sudo kubeadm token create --print-join-command")
    cert_key=$(ssh ubuntu@192.168.0.11 "sudo kubeadm init phase upload-certs --upload-certs 2>&1 | grep 'Using certificate key:' | awk '{print \$NF}'")

    # 讓其他 master 節點加入
    log_info "讓 master-2 加入集群..."
    ssh ubuntu@192.168.0.12 "sudo systemctl stop kubelet && sudo kubeadm reset --force && sudo systemctl restart containerd"
    ssh ubuntu@192.168.0.12 "sudo $join_cmd --control-plane --certificate-key $cert_key"

    log_info "讓 master-3 加入集群..."
    ssh ubuntu@192.168.0.13 "sudo systemctl stop kubelet && sudo kubeadm reset --force && sudo systemctl restart containerd"
    ssh ubuntu@192.168.0.13 "sudo $join_cmd --control-plane --certificate-key $cert_key"

    # 讓 worker 節點加入
    log_info "讓 app 節點加入集群..."
    ssh ubuntu@192.168.0.14 "sudo systemctl stop kubelet && sudo kubeadm reset --force && sudo systemctl restart containerd"
    ssh ubuntu@192.168.0.14 "sudo $join_cmd"

    log_info "讓 ai 節點加入集群..."
    ssh ubuntu@192.168.0.15 "sudo systemctl stop kubelet && sudo kubeadm reset --force && sudo systemctl restart containerd"
    ssh ubuntu@192.168.0.15 "sudo $join_cmd"

    log_success "HA 集群修復完成"
}

# 清理網路配置
network_cleanup() {
    log_info "清理網路配置殘留..."

    # 首先清理 SSH known_hosts 以避免連接問題
    log_info "清理 SSH known_hosts 以確保連接正常..."
    fix_ssh_keys

    # 等待 SSH 清理生效
    log_info "等待 SSH 配置生效..."
    sleep 3

    # 檢查網路配置狀態
    log_info "檢查當前網路配置狀態..."
    ansible_cmd "master-2" "shell" "ip link show && ip route show | grep -E '(tunl|cali|bird)' || echo 'No problematic routes found'"

    # 清理 tunl0 接口
    log_info "清理 tunl0 接口..."
    ansible_cmd "master-2" "shell" "sudo ip link delete tunl0 2>/dev/null || true"

    # 清理 kube-ipvs0 接口
    log_info "清理 kube-ipvs0 接口..."
    ansible_cmd "master-2" "shell" "sudo ip link delete kube-ipvs0 2>/dev/null || true"

    # 清理 Calico/BIRD 路由
    log_info "清理 Calico/BIRD 路由..."
    ansible_cmd "master-2" "shell" "sudo ip route flush proto bird 2>/dev/null || true"

    # 重置 iptables 和 IPVS 表
    log_info "重置 iptables 和 IPVS 表..."
    ansible_cmd "master-2" "shell" "sudo iptables -F && sudo iptables -X && sudo iptables -t nat -F && sudo iptables -t nat -X && sudo iptables -t mangle -F && sudo iptables -t mangle -X"
    ansible_cmd "master-2" "shell" "sudo ipvsadm --clear 2>/dev/null || true"

    # 重啟網路服務
    log_info "重啟網路服務..."
    ansible_cmd "master-2" "shell" "sudo systemctl restart systemd-networkd 2>/dev/null || true"

    # 測試網路連通性
    log_info "測試網路連通性恢復..."
    ansible_cmd "master-2" "shell" "ping -c 3 192.168.0.11"
    ansible_cmd "master-2" "shell" "curl -k --connect-timeout 5 https://192.168.0.11:6443/healthz"

    log_success "網路清理完成"
}

# 完整修復流程
full_recovery() {
    log_info "執行完整的集群修復流程..."

    # 步驟 1: 修復 SSH 問題（優先處理）
    fix_ssh_keys

    # 步驟 2: 檢查 etcd 狀態
    if check_etcd_status; then
        log_info "etcd 狀態正常，跳過清理"
    else
        cleanup_etcd
    fi

    # 步驟 3: 重置集群
    reset_cluster

    # 步驟 4: 清理網路配置
    network_cleanup

    log_success "完整集群修復流程完成"
    log_info "現在可以重新運行 Ansible 部署"
}

# 主邏輯
case "$ACTION" in
    check-etcd)
        check_etcd_status
        ;;
    cleanup-etcd)
        cleanup_etcd
        ;;
    reset-cluster)
        reset_cluster
        ;;
    fix-ssh-keys)
        fix_ssh_keys
        ;;
    manual-ha-fix)
        manual_ha_fix
        ;;
    network-cleanup)
        network_cleanup
        ;;
    full-recovery)
        full_recovery
        ;;
    *)
        log_error "未知動作: $ACTION"
        echo
        show_help
        exit 1
        ;;
esac
