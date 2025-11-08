#!/bin/bash
set -e

# ==============================================================================
# DetectViz Platform - Health Check Script v1.0
# 基礎健康檢查，專注於服務運行狀態
# ==============================================================================
#
# Usage:
#   ./scripts/health-check.sh                 # Run all checks
#   ./scripts/health-check.sh --phase2        # Run checks for Phase 2
#   ./scripts/health-check.sh --pre-vip-check # Run pre-VIP checks
#   ./scripts/health-check.sh --phase3        # Run checks for Phase 3
#   ./scripts/health-check.sh --phase9        # Run checks for Phase 9
#   ./scripts/health-check.sh --phase10       # Run checks for Phase 10
#
# ==============================================================================

# --- Helper Functions ---
info() {
    echo "[INFO] ------------------------------------------------"
    echo "[INFO] $1"
    echo "[INFO] ------------------------------------------------"
}

check() {
    echo -n "[CHECK] $1: "
    if eval $2; then
        echo "✅ PASSED"
        return 0
    else
        echo "❌ FAILED"
        return 1
    fi
}

# --- Check Functions ---

check_phase2() {
    info "Running Phase 2 Checks: Kubernetes Cluster Initialization"
    check "Node count is correct (at least 2 nodes)" "kubectl get nodes --no-headers | wc -l | xargs test 2 -le"
    check "All nodes are in 'Ready' state" "! kubectl get nodes | grep -v 'Ready'"
    check "No system pods are in a non-Running state" "kubectl get pods -n kube-system --field-selector=status.phase!=Running | grep -v 'Completed' | wc -l | xargs test 0 -eq"
    check "Etcd is running as a single-member cluster" "kubectl exec -n kube-system etcd-master-1.detectviz.internal -- etcdctl member list | wc -l | xargs test 1 -eq"
    check "Kubernetes admin RBAC is configured" "kubectl auth can-i get nodes --as=kubernetes-admin | grep -q 'yes'"
    check "Internal DNS resolution is working" "kubectl run test-pod --image=busybox --rm -i --restart=Never -- wget -O- http://kubernetes.default.svc.cluster.local >/dev/null 2>&1"
}

check_pre_vip() {
    info "Running Pre-VIP Checks: Network and API Server Sanity"
    check "API Server is healthy" "curl -k https://192.168.0.11:6443/healthz | grep -q 'ok'"
    check "No stale network interfaces (tunl0, kube-ipvs0)" "! ip link show | grep -E '(tunl|kube-ipvs)'"
}

check_phase3() {
    info "Running Phase 3 Checks: Kube-VIP High Availability"
    check "Kube-VIP DaemonSet is running" "kubectl get daemonset kube-vip-ds -n kube-system"
    check "kubeadm-config controlPlaneEndpoint is set to VIP" "kubectl get configmap kubeadm-config -n kube-system -o jsonpath='{.data.ClusterConfiguration}' | grep -q 'controlPlaneEndpoint: 192.168.0.10:6443'"
    check "API Server certificate contains VIP" "sudo openssl x509 -in /etc/kubernetes/pki/apiserver.crt -text -noout | grep -q '192.168.0.10'"
    check "VIP is reachable via ICMP" "ping -c 3 192.168.0.10"
    check "API Server is accessible via VIP" "curl -k --connect-timeout 5 https://192.168.0.10:6443/healthz | grep -q 'ok'"
    check "kubectl can connect via VIP" "kubectl --server https://192.168.0.10:6443 cluster-info"
}

check_phase9() {
    info "Running Phase 9 Checks: ArgoCD GitOps Control Plane"
    check "ArgoCD ApplicationSets are present" "kubectl get applicationsets -n argocd | grep -q 'infrastructure'"
    check "ArgoCD root application is present" "kubectl get applications -n argocd | grep -q 'root-argocd-app'"
    check "All ArgoCD core components are running" "kubectl get pods -n argocd | grep -E '(dex-server|applicationset-controller|notifications-controller|repo-server|server)' | grep Running | wc -l | xargs test 5 -le"
}

check_phase10() {
    info "Running Phase 10 Checks: Vault and External Secrets Operator"
    check "Vault is running and unsealed" "kubectl exec -n vault statefulset/vault -c vault -- vault status | grep -q 'Sealed.*false'"
    check "External Secrets Operator is running" "kubectl get pods -n external-secrets-system --field-selector=status.phase=Running | wc -l | xargs test 1 -le"
    check "Vault SecretStore is configured" "kubectl get secretstore vault-backend -n detectviz"
}

# --- Main Logic ---

if [ "$1" == "--phase2" ]; then
    check_phase2
elif [ "$1" == "--pre-vip-check" ]; then
    check_pre_vip
elif [ "$1" == "--phase3" ]; then
    check_phase3
elif [ "$1" == "--phase9" ]; then
    check_phase9
elif [ "$1" == "--phase10" ]; then
    check_phase10
elif [ "$1" == "--all" ] || [ -z "$1" ]; then
    check_phase2
    check_pre_vip
    check_phase3
    check_phase9
    check_phase10
else
    echo "Unknown argument: $1"
    exit 1
fi

echo ""
echo "✅ All specified health checks passed successfully."
