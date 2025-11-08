#!/bin/bash
set -eo pipefail

# ============================================================================
# kube-vip Pod 恢復測試腳本
#
# 用途: 測試 kube-vip 的 Pod 重建和恢復機制
# 測試場景: 刪除 Leader Pod，驗證 DaemonSet 自動重建和 Leader 恢復
# 版本: 2.0
# 日期: 2025-10-24
#
# 說明:
#   - 此腳本測試 Pod 層級的故障恢復 (DaemonSet 重建機制)
#   - 若需測試節點層級的故障轉移，請使用 test-node-failover.sh
# ============================================================================

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置變數
VIP_ADDRESS="${VIP_ADDRESS:-192.168.0.10}"
VIP_PORT="${VIP_PORT:-6443}"
PING_INTERVAL=1  # 秒
AUTO_CONFIRM=false  # 自動確認模式

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

# 錯誤處理
error_exit() {
    log_error "$1"
    exit 1
}

# 獲取當前 Leader
get_current_leader() {
    kubectl get lease -n kube-system plndr-cp-lock -o jsonpath='{.spec.holderIdentity}' 2>/dev/null || echo ""
}

# 獲取 Lease Transitions 計數
get_lease_transitions() {
    kubectl get lease -n kube-system plndr-cp-lock -o jsonpath='{.spec.leaseTransitions}' 2>/dev/null || echo "0"
}

# 獲取指定節點上的 kube-vip Pod 年齡 (秒)
get_pod_age_seconds() {
    local node_name="$1"
    local pod_start_time=$(kubectl get pods -n kube-system \
        -l app.kubernetes.io/name=kube-vip-ds \
        --field-selector spec.nodeName="$node_name" \
        -o jsonpath='{.items[0].status.startTime}' 2>/dev/null)

    if [ -z "$pod_start_time" ]; then
        echo "0"
        return
    fi

    local start_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$pod_start_time" +%s 2>/dev/null || echo "0")
    local now_epoch=$(date +%s)
    echo $((now_epoch - start_epoch))
}

# 獲取 Leader IP
get_leader_ip() {
    local leader_name="$1"
    kubectl get node "$leader_name" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo ""
}

# 檢查 VIP 可達性
check_vip_reachable() {
    ping -c 1 -W 1 "$VIP_ADDRESS" &> /dev/null
}

# 檢查 API Server 可達性
check_api_reachable() {
    curl -sk "https://$VIP_ADDRESS:$VIP_PORT/healthz" 2>/dev/null | grep -q "ok"
}

# 監控 VIP 可達性 (背景執行)
monitor_vip() {
    local log_file="$1"
    echo "開始時間,狀態,延遲" > "$log_file"

    while true; do
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        if ping -c 1 -W 1 "$VIP_ADDRESS" &> /dev/null; then
            local latency=$(ping -c 1 "$VIP_ADDRESS" 2>/dev/null | grep 'time=' | awk -F'time=' '{print $2}' | awk '{print $1}')
            echo "$timestamp,UP,$latency" >> "$log_file"
        else
            echo "$timestamp,DOWN,N/A" >> "$log_file"
        fi
        sleep "$PING_INTERVAL"
    done
}

# 前置檢查
pre_check() {
    log_info "執行前置檢查..."

    # 檢查 kubectl
    if ! command -v kubectl &> /dev/null; then
        error_exit "kubectl 未安裝"
    fi

    # 檢查集群連接
    if ! kubectl cluster-info &> /dev/null; then
        error_exit "無法連接到 Kubernetes 集群"
    fi

    # 檢查 kube-vip 是否部署
    local pod_count=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=kube-vip-ds --no-headers 2>/dev/null | wc -l | xargs)
    if [ "$pod_count" -eq 0 ]; then
        error_exit "kube-vip 尚未部署，請先執行 install-kube-vip.sh"
    fi
    log_success "kube-vip 已部署 ($pod_count 個 Pod)"

    # 檢查當前 Leader
    CURRENT_LEADER=$(get_current_leader)
    if [ -z "$CURRENT_LEADER" ]; then
        error_exit "無法獲取當前 Leader，請檢查 kube-vip 狀態"
    fi
    log_success "當前 Leader: $CURRENT_LEADER"

    # 檢查 VIP 可達性
    if ! check_vip_reachable; then
        error_exit "VIP $VIP_ADDRESS 不可達，請先解決此問題"
    fi
    log_success "VIP $VIP_ADDRESS 可達"

    # 檢查 API Server
    if ! check_api_reachable; then
        log_warning "API Server 無法通過 VIP 訪問，但仍繼續測試"
    else
        log_success "API Server 可通過 VIP 訪問"
    fi
}

# 執行故障轉移測試
run_failover_test() {
    log_info "開始故障轉移測試..."
    echo ""

    # 1. 記錄初始狀態
    INITIAL_LEADER=$(get_current_leader)
    INITIAL_LEADER_IP=$(get_leader_ip "$INITIAL_LEADER")
    INITIAL_TRANSITIONS=$(get_lease_transitions)
    INITIAL_POD_AGE=$(get_pod_age_seconds "$INITIAL_LEADER")

    log_info "📋 初始狀態："
    echo "  - Leader 節點: $INITIAL_LEADER"
    echo "  - Leader IP: $INITIAL_LEADER_IP"
    echo "  - VIP: $VIP_ADDRESS:$VIP_PORT"
    echo "  - Lease Transitions: $INITIAL_TRANSITIONS"
    echo "  - Pod 運行時間: ${INITIAL_POD_AGE}s"
    echo ""

    # 2. 啟動 VIP 監控 (背景執行)
    MONITOR_LOG=$(mktemp)
    log_info "啟動 VIP 監控 (記錄到 $MONITOR_LOG)..."
    monitor_vip "$MONITOR_LOG" &
    MONITOR_PID=$!
    sleep 2  # 等待監控啟動

    # 3. 警告用戶
    log_warning "⚠️  即將刪除當前 Leader 的 kube-vip Pod"
    log_warning "⚠️  此測試驗證 Pod 重建和恢復機制"
    log_warning "⚠️  預期停機時間: 3-10 秒"
    echo ""

    if [ "$AUTO_CONFIRM" = false ]; then
        read -p "是否繼續? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            kill $MONITOR_PID 2>/dev/null
            log_info "已取消測試"
            exit 0
        fi
    else
        log_info "自動確認模式，繼續執行測試..."
    fi

    # 4. 記錄故障轉移開始時間
    FAILOVER_START=$(date +%s)
    log_info "故障轉移開始: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    # 5. 刪除當前 Leader 的 kube-vip Pod
    log_info "刪除 Leader Pod..."
    kubectl delete pod -n kube-system \
        -l app.kubernetes.io/name=kube-vip-ds \
        --field-selector spec.nodeName="$INITIAL_LEADER" \
        &> /dev/null || log_warning "Pod 刪除失敗，但繼續測試"

    # 6. 等待 Pod 重建和 Leader 恢復
    log_info "等待 Pod 重建和 Leader 恢復..."
    local max_wait=60
    local waited=0
    NEW_LEADER=""
    POD_REBUILT=0

    while [ $waited -lt $max_wait ]; do
        sleep 1
        waited=$((waited + 1))

        # 檢查是否有 Leader (可能暫時無 Leader)
        NEW_LEADER=$(get_current_leader)

        # 檢查 Pod 是否已重建 (年齡 < 初始年齡，表示是新 Pod)
        if [ -n "$NEW_LEADER" ]; then
            CURRENT_POD_AGE=$(get_pod_age_seconds "$NEW_LEADER")

            # 如果 Leader 改變到其他節點 (節點故障轉移)
            if [ "$NEW_LEADER" != "$INITIAL_LEADER" ]; then
                FAILOVER_END=$(date +%s)
                FAILOVER_DURATION=$((FAILOVER_END - FAILOVER_START))
                log_success "Leader 已轉移到其他節點: $NEW_LEADER  (耗時 ${FAILOVER_DURATION}s)"
                POD_REBUILT=1
                break
            fi

            # 如果 Leader 還是原節點但 Pod 已重建 (Pod 年齡 < 初始年齡 - 30s)
            if [ "$NEW_LEADER" == "$INITIAL_LEADER" ] && [ "$CURRENT_POD_AGE" -lt $((INITIAL_POD_AGE - 20)) ]; then
                FAILOVER_END=$(date +%s)
                FAILOVER_DURATION=$((FAILOVER_END - FAILOVER_START))
                log_success "Pod 已重建並恢復 Leader  (耗時 ${FAILOVER_DURATION}s，新 Pod 年齡: ${CURRENT_POD_AGE}s)"
                POD_REBUILT=1
                break
            fi
        fi

        echo -ne "\r  等待中... ${waited}s"
    done
    echo ""

    if [ $POD_REBUILT -eq 0 ]; then
        log_error "Pod 恢復失敗或超時"
        log_info "當前 Leader: ${NEW_LEADER:-無}"
        log_info "當前 Pod 年齡: $(get_pod_age_seconds "$NEW_LEADER" 2>/dev/null || echo "無法獲取")s"
        kill $MONITOR_PID 2>/dev/null
        return 1
    fi

    # 7. 等待 VIP 恢復
    log_info "等待 VIP 恢復可達性..."
    local vip_recovered=0
    waited=0

    while [ $waited -lt $max_wait ]; do
        sleep 1
        waited=$((waited + 1))

        if check_vip_reachable; then
            VIP_RECOVERY_TIME=$(($(date +%s) - FAILOVER_START))
            log_success "VIP 已恢復可達 (總耗時 ${VIP_RECOVERY_TIME}s)"
            vip_recovered=1
            break
        fi

        echo -ne "\r  等待中... ${waited}s"
    done
    echo ""

    if [ $vip_recovered -eq 0 ]; then
        log_error "VIP 恢復失敗"
        kill $MONITOR_PID 2>/dev/null
        return 1
    fi

    # 8. 驗證 API Server 可訪問性
    log_info "驗證 API Server 可訪問性..."
    sleep 2  # 給 API Server 一點時間

    if check_api_reachable; then
        log_success "API Server 可通過 VIP 訪問"
    else
        log_warning "API Server 無法通過 VIP 訪問 (可能需要更多時間)"
    fi

    # 9. 停止監控
    sleep 5  # 收集更多數據
    kill $MONITOR_PID 2>/dev/null

    # 10. 分析監控數據
    echo ""
    log_info "分析故障轉移過程..."
    analyze_failover_data "$MONITOR_LOG" "$FAILOVER_START"

    # 11. 清理臨時檔案
    rm -f "$MONITOR_LOG"

    return 0
}

# 分析故障轉移數據
analyze_failover_data() {
    local log_file="$1"
    local failover_start="$2"

    # 統計停機時間
    local down_count=$(grep ",DOWN," "$log_file" | wc -l | xargs)
    local total_count=$(tail -n +2 "$log_file" | wc -l | xargs)
    local downtime=$((down_count * PING_INTERVAL))

    echo ""
    echo "=========================================="
    log_info "📊 故障轉移分析結果"
    echo "=========================================="
    echo ""
    echo "⏱️  時間指標："
    echo "  - 故障檢測時間: ~${FAILOVER_DURATION}s"
    echo "  - VIP 遷移時間: ~${VIP_RECOVERY_TIME}s"
    echo "  - VIP 停機時間: ~${downtime}s"
    echo "  - 總測試時間: ~$(($(date +%s) - failover_start))s"
    echo ""
    echo "🔄 恢復機制："
    if [ "$NEW_LEADER" != "$INITIAL_LEADER" ]; then
        echo "  - 初始 Leader: $INITIAL_LEADER"
        echo "  - 新 Leader: $NEW_LEADER"
        echo "  - 類型: 節點故障轉移"
    else
        echo "  - Leader 節點: $INITIAL_LEADER (未改變)"
        echo "  - 初始 Pod 年齡: ${INITIAL_POD_AGE}s"
        echo "  - 當前 Pod 年齡: $(get_pod_age_seconds "$NEW_LEADER")s"
        echo "  - 類型: Pod 重建恢復"
    fi
    echo ""
    echo "📈 可用性統計："
    echo "  - 總 ping 次數: $total_count"
    echo "  - 失敗次數: $down_count"
    if [ "$total_count" -gt 0 ]; then
        local availability=$(echo "scale=2; (1 - $down_count / $total_count) * 100" | bc)
        echo "  - 可用性: ${availability}%"
    else
        echo "  - 可用性: N/A"
    fi
    echo ""

    # 顯示詳細日誌 (可選)
    if [ "$down_count" -gt 0 ]; then
        log_info "停機期間詳細記錄:"
        grep ",DOWN," "$log_file" | head -10
        echo ""
    fi

    # 評估結果
    if [ "$downtime" -le 10 ]; then
        log_success "✅ 故障轉移性能優秀 (停機時間 ≤ 10s)"
    elif [ "$downtime" -le 30 ]; then
        log_success "✅ 故障轉移性能良好 (停機時間 ≤ 30s)"
    else
        log_warning "⚠️  故障轉移時間較長 (停機時間 > 30s)，建議檢查配置"
    fi
}

# 驗證集群狀態
verify_cluster_state() {
    echo ""
    log_info "驗證集群最終狀態..."

    # 1. 檢查所有 kube-vip Pod
    log_info "kube-vip Pod 狀態："
    kubectl get pods -n kube-system -l app.kubernetes.io/name=kube-vip-ds -o wide
    echo ""

    # 2. 檢查所有節點
    log_info "集群節點狀態："
    kubectl get nodes -o wide
    echo ""

    # 3. 檢查 Leader
    FINAL_LEADER=$(get_current_leader)
    log_info "當前 Leader: $FINAL_LEADER"
    echo ""

    # 4. 檢查 Lease
    log_info "Leader Lease 詳情："
    kubectl get lease -n kube-system plndr-cp-lock -o yaml | grep -E 'holderIdentity|renewTime|leaseDurationSeconds'
    echo ""
}

# 主函數
main() {
    # 解析命令行參數
    while [[ $# -gt 0 ]]; do
        case $1 in
            -y|--yes)
                AUTO_CONFIRM=true
                shift
                ;;
            -h|--help)
                echo "用法: $0 [選項]"
                echo ""
                echo "選項:"
                echo "  -y, --yes    自動確認，跳過確認提示"
                echo "  -h, --help   顯示此幫助訊息"
                echo ""
                echo "範例:"
                echo "  $0           # 互動模式 (需要確認)"
                echo "  $0 --yes     # 自動模式 (跳過確認)"
                exit 0
                ;;
            *)
                echo "未知選項: $1"
                echo "使用 --help 查看幫助"
                exit 1
                ;;
        esac
    done

    echo "=========================================="
    echo "  kube-vip Pod 恢復測試"
    echo "=========================================="
    echo ""

    log_info "測試類型: Pod 層級故障恢復"
    log_info "測試方法: 刪除 Leader Pod，驗證 DaemonSet 重建"
    echo ""

    log_warning "⚠️  此測試將暫時刪除 kube-vip Pod"
    log_warning "⚠️  預期停機時間: 3-10 秒"
    log_warning "⚠️  建議在非生產環境或維護時段執行"
    echo ""

    # 執行測試流程
    pre_check
    echo ""

    if run_failover_test; then
        verify_cluster_state
        log_success "✅ Pod 恢復測試完成！"
        echo ""
        log_info "💡 提示: 若需測試節點層級故障轉移，請執行:"
        echo "      ./test-node-failover.sh"
    else
        log_error "❌ Pod 恢復測試失敗，請檢查日誌"
        exit 1
    fi
}

# 執行主函數
main "$@"
