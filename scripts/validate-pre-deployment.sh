#!/usr/bin/env bash
#
# DetectViz Pre-Deployment Validation Script
#
# Purpose: Validate infrastructure readiness before deploying applications
# Phase: 7.1 (Pre-deployment validation)
#
# Usage: ./scripts/validate-pre-deployment.sh
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

# Check if vault CLI is available (optional)
VAULT_CLI_AVAILABLE=false
if command -v vault &> /dev/null; then
    VAULT_CLI_AVAILABLE=true
fi

print_header "Phase 7.1: Pre-Deployment Validation"

# ============================================
# 1. ArgoCD ApplicationSet Check
# ============================================
print_header "1. ArgoCD ApplicationSet Validation"

print_check "ApplicationSet 'apps-appset' exists"
if kubectl get applicationset apps-appset -n argocd &>/dev/null; then
    print_pass "ApplicationSet 'apps-appset' found"
else
    print_fail "ApplicationSet 'apps-appset' not found"
fi

print_check "ApplicationSet generator type"
GENERATOR_TYPE=$(kubectl get applicationset apps-appset -n argocd -o jsonpath='{.spec.generators[0]}' 2>/dev/null | grep -q "list" && echo "list" || echo "other")
if [ "$GENERATOR_TYPE" = "list" ]; then
    print_pass "Using List generator (correct)"
else
    print_fail "Not using List generator (should be 'list', found '$GENERATOR_TYPE')"
fi

print_check "Generated Applications"
APPS=(postgresql keycloak grafana prometheus loki tempo mimir minio alertmanager)
for app in "${APPS[@]}"; do
    if kubectl get application "$app" -n argocd &>/dev/null; then
        print_info "  ✓ Application '$app' exists"
    else
        print_warn "  ✗ Application '$app' not found (may not be generated yet)"
    fi
done

# ============================================
# 2. Vault Secrets Validation
# ============================================
print_header "2. Vault Secrets Validation"

if [ "$VAULT_CLI_AVAILABLE" = true ]; then
    print_info "Vault CLI available - checking secrets"

    # Check PostgreSQL secrets
    print_check "PostgreSQL secrets in Vault"
    if vault kv get secret/postgresql/admin &>/dev/null; then
        print_pass "PostgreSQL admin secrets found"
    else
        print_fail "PostgreSQL admin secrets not found - initialize with: vault kv put secret/postgresql/admin ..."
    fi

    if vault kv get secret/postgresql/initdb &>/dev/null; then
        print_pass "PostgreSQL initdb secrets found"
    else
        print_fail "PostgreSQL initdb secrets not found"
    fi

    # Check Keycloak secrets
    print_check "Keycloak secrets in Vault"
    if vault kv get secret/keycloak/database &>/dev/null; then
        print_pass "Keycloak database secrets found"
    else
        print_fail "Keycloak database secrets not found"
    fi

    # Check Grafana secrets
    print_check "Grafana secrets in Vault"
    if vault kv get secret/grafana/admin &>/dev/null; then
        print_pass "Grafana admin secrets found"
    else
        print_fail "Grafana admin secrets not found"
    fi

    if vault kv get secret/grafana/database &>/dev/null; then
        print_pass "Grafana database secrets found"
    else
        print_fail "Grafana database secrets not found"
    fi

    if vault kv get secret/grafana/oauth &>/dev/null; then
        print_pass "Grafana OAuth secrets found"
    else
        print_fail "Grafana OAuth secrets not found"
    fi

    # Check Minio secrets
    print_check "Minio secrets in Vault"
    if vault kv get secret/monitoring/minio &>/dev/null; then
        MINIO_KEYS=$(vault kv get -format=json secret/monitoring/minio 2>/dev/null | jq -r '.data.data | keys[]' 2>/dev/null)
        REQUIRED_KEYS=("root-user" "root-password" "mimir-access-key" "mimir-secret-key")
        ALL_FOUND=true
        for key in "${REQUIRED_KEYS[@]}"; do
            if echo "$MINIO_KEYS" | grep -q "^$key$"; then
                print_info "  ✓ Minio key '$key' found"
            else
                print_fail "  ✗ Minio key '$key' not found"
                ALL_FOUND=false
            fi
        done
        if [ "$ALL_FOUND" = true ]; then
            print_pass "All Minio secrets found"
        fi
    else
        print_fail "Minio secrets not found"
    fi
else
    print_warn "Vault CLI not available - skipping Vault secrets validation"
    print_info "Install vault CLI or manually verify secrets in Vault UI"
fi

# ============================================
# 3. Namespace Readiness
# ============================================
print_header "3. Namespace Readiness"

print_check "Required namespaces"
NAMESPACES=(postgresql keycloak grafana monitoring)
for ns in "${NAMESPACES[@]}"; do
    if kubectl get namespace "$ns" &>/dev/null; then
        print_info "  ✓ Namespace '$ns' exists"
    else
        print_info "  ℹ  Namespace '$ns' will be created during deployment"
    fi
done

# ============================================
# 4. External Secrets Operator
# ============================================
print_header "4. External Secrets Operator"

print_check "ESO pods running"
ESO_PODS=$(kubectl get pods -n external-secrets-system -l app.kubernetes.io/name=external-secrets 2>/dev/null | grep -c Running || echo "0")
if [ "$ESO_PODS" -gt 0 ]; then
    print_pass "External Secrets Operator running ($ESO_PODS pods)"
else
    print_fail "External Secrets Operator not running"
fi

print_check "ClusterSecretStore 'vault-backend'"
if kubectl get clustersecretstore vault-backend &>/dev/null; then
    print_pass "ClusterSecretStore 'vault-backend' found"

    # Check if it's ready
    STATUS=$(kubectl get clustersecretstore vault-backend -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
    if [ "$STATUS" = "True" ]; then
        print_pass "ClusterSecretStore is Ready"
    else
        print_warn "ClusterSecretStore status: $STATUS (should be 'True')"
    fi
else
    print_fail "ClusterSecretStore 'vault-backend' not found"
fi

# ============================================
# 5. Storage Classes
# ============================================
print_header "5. Storage Classes"

print_check "StorageClass 'topolvm-provisioner'"
if kubectl get storageclass topolvm-provisioner &>/dev/null; then
    print_pass "StorageClass 'topolvm-provisioner' available"
else
    print_fail "StorageClass 'topolvm-provisioner' not found (required for PostgreSQL, Minio, Tempo)"
fi

print_check "StorageClass 'local-path'"
if kubectl get storageclass local-path &>/dev/null; then
    print_pass "StorageClass 'local-path' available"
else
    print_warn "StorageClass 'local-path' not found (required for Prometheus, Loki)"
fi

# ============================================
# Summary
# ============================================
print_header "Validation Summary"

echo -e "${GREEN}Passed:   $PASSED${NC}"
echo -e "${YELLOW}Warnings: $WARNINGS${NC}"
echo -e "${RED}Failed:   $FAILED${NC}"

if [ $FAILED -eq 0 ]; then
    echo -e "\n${GREEN}🎉 Pre-deployment validation passed!${NC}"
    echo -e "${BLUE}You can proceed with deploying applications via ArgoCD.${NC}"
    exit 0
elif [ $FAILED -le 2 ]; then
    echo -e "\n${YELLOW}⚠️  Pre-deployment validation completed with minor issues.${NC}"
    echo -e "${YELLOW}Review failed checks and fix them before deployment.${NC}"
    exit 1
else
    echo -e "\n${RED}❌ Pre-deployment validation failed!${NC}"
    echo -e "${RED}Please fix the failed checks before proceeding.${NC}"
    exit 1
fi
