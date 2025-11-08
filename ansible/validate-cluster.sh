#!/bin/bash

# ============================================
# Detectviz Kubernetes 集群驗證腳本
# 運行此腳本以驗證集群部署
# ============================================

set -e  # 遇到錯誤立即退出

echo "🔍 Validating Detectviz Kubernetes Cluster..."
echo "=============================================="

# 輸出顏色定義
RED='\033[0;31m'     # 紅色 - 用於錯誤
GREEN='\033[0;32m'   # 綠色 - 用於成功
YELLOW='\033[1;33m'  # 黃色 - 用於警告
NC='\033[0m'         # 無顏色 - 重置

# 打印狀態函數
print_status() {
    local status=$1    # 狀態碼 (0=成功, 其他=失敗)
    local message=$2   # 狀態訊息
    if [ "$status" -eq 0 ]; then
        echo -e "${GREEN}✅ $message${NC}"  # 成功訊息
    else
        echo -e "${RED}❌ $message${NC}"    # 錯誤訊息
    fi
}

# 檢查是否在 master 節點上運行
if [ ! -f "/etc/kubernetes/admin.conf" ]; then
    echo -e "${RED}❌ 不在 Kubernetes master 節點上運行${NC}"
    echo "此腳本應在具有 kubectl 訪問權限的 master 節點上運行"
    exit 1
fi

export KUBECONFIG=/etc/kubernetes/admin.conf  # 設置 kubeconfig 環境變數

echo "📊 集群資訊:"
echo "-----------------------"
kubectl cluster-info  # 顯示集群基本資訊
echo

echo "🖥️  節點狀態:"
echo "---------------"
kubectl get nodes -o wide  # 顯示節點詳細狀態
echo

echo "🔍 詳細驗證:"
echo "----------------------"

# Check node count
NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
if [ "$NODE_COUNT" -eq 5 ]; then
    print_status 0 "All 5 nodes are present (3 masters + 2 workers)"
else
    print_status 1 "Expected 5 nodes, found $NODE_COUNT"
fi

# Check node readiness
NOT_READY=$(kubectl get nodes --no-headers | grep -v Ready | wc -l)
if [ "$NOT_READY" -eq 0 ]; then
    print_status 0 "All nodes are Ready"
else
    print_status 1 "$NOT_READY nodes are not Ready"
fi

# Check control plane pods
echo
echo "🎛️  Control Plane Status:"
echo "------------------------"
kubectl get pods -n kube-system -l tier=control-plane -o wide

CP_PODS_TOTAL=$(kubectl get pods -n kube-system -l tier=control-plane --no-headers | wc -l)
CP_PODS_READY=$(kubectl get pods -n kube-system -l tier=control-plane --no-headers | grep "1/1" | wc -l)

if [ "$CP_PODS_READY" -eq "$CP_PODS_TOTAL" ] && [ "$CP_PODS_TOTAL" -gt 0 ]; then
    print_status 0 "All control plane pods are running ($CP_PODS_READY/$CP_PODS_TOTAL)"
else
    print_status 1 "Control plane pods: $CP_PODS_READY/$CP_PODS_TOTAL ready"
fi

# Check system pods
echo
echo "🔧 System Services:"
echo "------------------"
kubectl get pods -n kube-system -o wide | head -20

# Check Calico
CALICO_READY=$(kubectl get pods -n kube-system -l k8s-app=calico-node --no-headers | grep Running | wc -l)
if [ "$CALICO_READY" -ge 4 ]; then
    print_status 0 "Calico CNI is running ($CALICO_READY pods)"
else
    print_status 1 "Calico CNI pods: $CALICO_READY running (expected >=4)"
fi

# Check CoreDNS
COREDNS_READY=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers | grep Running | wc -l)
if [ "$COREDNS_READY" -ge 2 ]; then
    print_status 0 "CoreDNS is running ($COREDNS_READY pods)"
else
    print_status 1 "CoreDNS pods: $COREDNS_READY running (expected >=2)"
fi

# Test pod creation
echo
echo "🧪 Testing Pod Creation:"
echo "-----------------------"
kubectl run test-pod --image=busybox --command -- sleep 30 --restart=Never 2>/dev/null || true

sleep 5

POD_STATUS=$(kubectl get pod test-pod --no-headers 2>/dev/null | awk '{print $3}' || echo "NotFound")
if [ "$POD_STATUS" = "Running" ]; then
    print_status 0 "Pod creation and scheduling works"
    kubectl delete pod test-pod --ignore-not-found=true >/dev/null 2>&1
elif [ "$POD_STATUS" = "Pending" ]; then
    print_status 1 "Pod created but not scheduled (networking issue?)"
    kubectl delete pod test-pod --ignore-not-found=true >/dev/null 2>&1
else
    print_status 1 "Pod creation failed"
fi

# Network connectivity test
echo
echo "🌐 Network Connectivity:"
echo "-----------------------"
kubectl run net-test --image=busybox --command -- sh -c "wget -qO- http://www.google.com >/dev/null && echo 'Internet access: OK' || echo 'Internet access: FAILED'" --restart=Never 2>/dev/null || true

sleep 10

NET_RESULT=$(kubectl logs net-test 2>/dev/null | tail -1 || echo "Test failed")
if [[ "$NET_RESULT" == *"OK"* ]]; then
    print_status 0 "Internet connectivity from pods works"
else
    print_status 1 "Internet connectivity test: $NET_RESULT"
fi

kubectl delete pod net-test --ignore-not-found=true >/dev/null 2>&1

echo
echo "📋 Summary:"
echo "==========="
echo "Cluster Endpoint: $(kubectl config view --minify | grep server | cut -d: -f2- | tr -d ' ')"
echo "Kubernetes Version: $(kubectl version --short 2>/dev/null | grep Server | cut -d: -f2 | tr -d ' ')"
echo "Nodes: $(kubectl get nodes --no-headers | wc -l) total"
echo "Ready Nodes: $(kubectl get nodes --no-headers | grep -c Ready)"
echo "System Pods: $(kubectl get pods -n kube-system --no-headers | wc -l) total"
echo "Running Pods: $(kubectl get pods -n kube-system --no-headers | grep -c Running)"

echo
echo "🎉 驗證完成！"
echo "======================"
echo "如果所有檢查都通過，您的 Detectviz 集群已準備好用於生產環境。"
echo "下一步：部署 ArgoCD、監控堆疊和您的應用程式。"
