#!/usr/bin/env bash
#
# DetectViz Post-Deployment Validation Script
#
# Purpose: Validate application deployment health and functionality
# Phase: 7.2 (Post-deployment validation)
#
# Usage: ./scripts/validate-post-deployment.sh
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0
WARNINGS=0

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_check() {
    echo -e "${YELLOW}🔍 Checking: $1${NC}"
}

print_pass() {
    echo -e "${GREEN}✅ PASS: $1${NC}"
    ((PASSED++))
}

print_fail() {
    echo -e "${RED}❌ FAIL: $1${NC}"
    ((FAILED++))
}

print_warn() {
    echo -e "${YELLOW}⚠️  WARN: $1${NC}"
    ((WARNINGS++))
}

print_info() {
    echo -e "${BLUE}ℹ️  INFO: $1${NC}"
}

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl not found. Please install kubectl.${NC}"
    exit 1
fi

print_header "Phase 7.2: Post-Deployment Validation"

# ============================================
# 1. Namespace Validation
# ============================================
print_header "1. Namespace Validation"

print_check "Required namespaces exist"
NAMESPACES=(postgresql keycloak grafana monitoring)
for ns in "${NAMESPACES[@]}"; do
    if kubectl get namespace "$ns" &>/dev/null; then
        print_pass "Namespace '$ns' exists"
    else
        print_fail "Namespace '$ns' not found"
    fi
done

# ============================================
# 2. ExternalSecrets Synchronization
# ============================================
print_header "2. ExternalSecrets Synchronization"

check_externalsecrets() {
    local namespace=$1
    local expected_count=$2

    print_check "ExternalSecrets in namespace '$namespace'"
    local count=$(kubectl get externalsecrets -n "$namespace" 2>/dev/null | grep -c externalsecrets.io || echo "0")
    if [ "$count" -ge "$expected_count" ]; then
        print_pass "Found $count ExternalSecret(s) in '$namespace'"

        # Check sync status
        local synced=$(kubectl get externalsecrets -n "$namespace" -o json 2>/dev/null | \
            jq -r '.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="True")) | .metadata.name' 2>/dev/null || echo "")

        if [ -n "$synced" ]; then
            while IFS= read -r es_name; do
                print_info "  ✓ ExternalSecret '$es_name' synced"
            done <<< "$synced"
        fi

        local failed=$(kubectl get externalsecrets -n "$namespace" -o json 2>/dev/null | \
            jq -r '.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status!="True")) | .metadata.name' 2>/dev/null || echo "")

        if [ -n "$failed" ]; then
            while IFS= read -r es_name; do
                print_fail "  ✗ ExternalSecret '$es_name' not ready"
            done <<< "$failed"
        fi
    else
        print_warn "Expected at least $expected_count ExternalSecret(s), found $count"
    fi
}

check_externalsecrets "postgresql" 1
check_externalsecrets "keycloak" 1
check_externalsecrets "grafana" 3
check_externalsecrets "monitoring" 2

# ============================================
# 3. Pod Health Status
# ============================================
print_header "3. Pod Health Status"

check_pods() {
    local namespace=$1
    local app_name=$2

    print_check "Pods in namespace '$namespace'"
    local total=$(kubectl get pods -n "$namespace" 2>/dev/null | tail -n +2 | wc -l || echo "0")
    local running=$(kubectl get pods -n "$namespace" --field-selector=status.phase=Running 2>/dev/null | tail -n +2 | wc -l || echo "0")

    if [ "$total" -eq 0 ]; then
        print_warn "No pods found in '$namespace'"
    elif [ "$total" -eq "$running" ]; then
        print_pass "All $total pods running in '$namespace'"
    else
        print_warn "$running/$total pods running in '$namespace'"

        # Show non-running pods
        kubectl get pods -n "$namespace" --field-selector=status.phase!=Running 2>/dev/null | tail -n +2 | while read -r line; do
            POD_NAME=$(echo "$line" | awk '{print $1}')
            POD_STATUS=$(echo "$line" | awk '{print $3}')
            print_info "  ✗ Pod '$POD_NAME': $POD_STATUS"
        done
    fi
}

check_pods "postgresql" "PostgreSQL HA"
check_pods "keycloak" "Keycloak"
check_pods "grafana" "Grafana"
check_pods "monitoring" "Observability Stack"

# ============================================
# 4. Service Availability
# ============================================
print_header "4. Service Availability"

check_service() {
    local namespace=$1
    local service_name=$2

    if kubectl get svc "$service_name" -n "$namespace" &>/dev/null; then
        local cluster_ip=$(kubectl get svc "$service_name" -n "$namespace" -o jsonpath='{.spec.clusterIP}')
        print_pass "Service '$service_name' in '$namespace' (ClusterIP: $cluster_ip)"
    else
        print_fail "Service '$service_name' not found in '$namespace'"
    fi
}

# PostgreSQL
check_service "postgresql" "postgresql-pgpool"

# Keycloak
check_service "keycloak" "keycloak"

# Grafana
check_service "grafana" "grafana"

# Monitoring
check_service "monitoring" "prometheus-kube-prometheus-prometheus"
check_service "monitoring" "loki-gateway"
check_service "monitoring" "mimir-query-frontend"
check_service "monitoring" "tempo"
check_service "monitoring" "minio"

# ============================================
# 5. Cross-Namespace Connectivity
# ============================================
print_header "5. Cross-Namespace Connectivity (Optional)"

print_info "Testing cross-namespace service connectivity requires running pods"
print_info "Skip this section if pods are still initializing"

# Try to find a grafana pod
GRAFANA_POD=$(kubectl get pods -n grafana -l app.kubernetes.io/name=grafana --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "$GRAFANA_POD" ]; then
    print_check "Grafana → PostgreSQL connectivity"
    if kubectl exec -n grafana "$GRAFANA_POD" -- sh -c "timeout 2 nc -zv postgresql-pgpool.postgresql.svc.cluster.local 5432" &>/dev/null; then
        print_pass "Grafana can reach PostgreSQL"
    else
        print_warn "Grafana cannot reach PostgreSQL (may need time to initialize)"
    fi

    print_check "Grafana → Mimir connectivity"
    if kubectl exec -n grafana "$GRAFANA_POD" -- sh -c "timeout 2 wget -q -O- http://mimir-query-frontend.monitoring.svc.cluster.local:8080/ready" &>/dev/null; then
        print_pass "Grafana can reach Mimir"
    else
        print_warn "Grafana cannot reach Mimir (may need time to initialize)"
    fi

    print_check "Grafana → Loki connectivity"
    if kubectl exec -n grafana "$GRAFANA_POD" -- sh -c "timeout 2 wget -q -O- http://loki-gateway.monitoring.svc.cluster.local:80/ready" &>/dev/null; then
        print_pass "Grafana can reach Loki"
    else
        print_warn "Grafana cannot reach Loki (may need time to initialize)"
    fi
else
    print_info "Grafana pod not running yet - skipping connectivity tests"
fi

# ============================================
# 6. Ingress Validation
# ============================================
print_header "6. Ingress Validation"

check_ingress() {
    local namespace=$1
    local ingress_name=$2
    local expected_host=$3

    if kubectl get ingress "$ingress_name" -n "$namespace" &>/dev/null; then
        local host=$(kubectl get ingress "$ingress_name" -n "$namespace" -o jsonpath='{.spec.rules[0].host}')
        if [ "$host" = "$expected_host" ]; then
            print_pass "Ingress '$ingress_name' configured for '$host'"
        else
            print_warn "Ingress '$ingress_name' host mismatch: expected '$expected_host', got '$host'"
        fi
    else
        print_warn "Ingress '$ingress_name' not found in '$namespace' (may not be configured yet)"
    fi
}

check_ingress "grafana" "grafana" "grafana.detectviz.internal"
check_ingress "keycloak" "keycloak" "keycloak.detectviz.internal"
check_ingress "monitoring" "prometheus" "prometheus.detectviz.internal"

# ============================================
# 7. PVC Status
# ============================================
print_header "7. Persistent Volume Claims"

check_pvcs() {
    local namespace=$1

    print_check "PVCs in namespace '$namespace'"
    local total=$(kubectl get pvc -n "$namespace" 2>/dev/null | tail -n +2 | wc -l || echo "0")
    local bound=$(kubectl get pvc -n "$namespace" --field-selector=status.phase=Bound 2>/dev/null | tail -n +2 | wc -l || echo "0")

    if [ "$total" -eq 0 ]; then
        print_info "No PVCs in '$namespace'"
    elif [ "$total" -eq "$bound" ]; then
        print_pass "All $total PVCs bound in '$namespace'"
    else
        print_warn "$bound/$total PVCs bound in '$namespace'"

        # Show non-bound PVCs
        kubectl get pvc -n "$namespace" --field-selector=status.phase!=Bound 2>/dev/null | tail -n +2 | while read -r line; do
            PVC_NAME=$(echo "$line" | awk '{print $1}')
            PVC_STATUS=$(echo "$line" | awk '{print $2}')
            print_info "  ✗ PVC '$PVC_NAME': $PVC_STATUS"
        done
    fi
}

check_pvcs "postgresql"
check_pvcs "grafana"
check_pvcs "monitoring"

# ============================================
# 8. Application-Specific Checks
# ============================================
print_header "8. Application-Specific Validation"

# PostgreSQL replication check
print_check "PostgreSQL replication status"
PG_POD=$(kubectl get pods -n postgresql -l app.kubernetes.io/component=postgresql --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$PG_POD" ]; then
    REPLICA_COUNT=$(kubectl exec -n postgresql "$PG_POD" -- psql -U postgres -t -c "SELECT count(*) FROM pg_stat_replication;" 2>/dev/null | tr -d ' ' || echo "0")
    if [ "$REPLICA_COUNT" -ge 1 ]; then
        print_pass "PostgreSQL replication active ($REPLICA_COUNT replicas)"
    else
        print_warn "PostgreSQL replication not detected (expected >= 1 replica)"
    fi
else
    print_info "PostgreSQL pod not running - skipping replication check"
fi

# Minio bucket check
print_check "Minio buckets for Mimir"
MINIO_POD=$(kubectl get pods -n monitoring -l app=minio --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$MINIO_POD" ]; then
    BUCKETS=$(kubectl exec -n monitoring "$MINIO_POD" -- sh -c "mc alias set local http://localhost:9000 \$MINIO_ROOT_USER \$MINIO_ROOT_PASSWORD &>/dev/null && mc ls local" 2>/dev/null | awk '{print $NF}' || echo "")
    REQUIRED_BUCKETS=("mimir-blocks/" "mimir-ruler/" "mimir-alertmanager/")
    ALL_FOUND=true
    for bucket in "${REQUIRED_BUCKETS[@]}"; do
        if echo "$BUCKETS" | grep -q "$bucket"; then
            print_info "  ✓ Bucket '$bucket' exists"
        else
            print_warn "  ✗ Bucket '$bucket' not found"
            ALL_FOUND=false
        fi
    done
    if [ "$ALL_FOUND" = true ]; then
        print_pass "All required Minio buckets exist"
    fi
else
    print_info "Minio pod not running - skipping bucket check"
fi

# ============================================
# Summary
# ============================================
print_header "Validation Summary"

echo -e "${GREEN}Passed:   $PASSED${NC}"
echo -e "${YELLOW}Warnings: $WARNINGS${NC}"
echo -e "${RED}Failed:   $FAILED${NC}"

if [ $FAILED -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "\n${GREEN}🎉 Post-deployment validation passed!${NC}"
    echo -e "${BLUE}All applications are healthy and ready.${NC}"
    exit 0
elif [ $FAILED -eq 0 ]; then
    echo -e "\n${YELLOW}⚠️  Post-deployment validation completed with warnings.${NC}"
    echo -e "${YELLOW}Review warnings - they may be transient during initialization.${NC}"
    exit 0
elif [ $FAILED -le 3 ]; then
    echo -e "\n${YELLOW}⚠️  Post-deployment validation completed with minor issues.${NC}"
    echo -e "${YELLOW}Review failed checks - some services may still be starting.${NC}"
    exit 1
else
    echo -e "\n${RED}❌ Post-deployment validation failed!${NC}"
    echo -e "${RED}Please investigate the failed checks.${NC}"
    exit 1
fi
