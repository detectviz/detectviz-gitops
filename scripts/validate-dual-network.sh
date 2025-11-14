#!/bin/bash
set -e

# ==============================================================================
# DetectViz Platform - Dual Network Validation Script
# 驗證雙網路架構配置 (vmbr0 + vmbr1)
# ==============================================================================
#
# Usage:
#   ./scripts/validate-dual-network.sh                    # Run all validations
#   ./scripts/validate-dual-network.sh --proxmox          # Validate Proxmox host
#   ./scripts/validate-dual-network.sh --vms              # Validate VMs
#   ./scripts/validate-dual-network.sh --dns              # Validate DNS
#
# ==============================================================================

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- Helper Functions ---
info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

error() {
    echo -e "${RED}[✗]${NC} $1"
}

validate_test() {
    local test_name="$1"
    local test_command="$2"

    echo -n "[TEST] $test_name: "
    if eval "$test_command" > /dev/null 2>&1; then
        success "PASSED"
        return 0
    else
        error "FAILED"
        return 1
    fi
}

# --- Validation Functions ---

validate_proxmox_host() {
    info "========================================="
    info "Validating Proxmox Host Configuration"
    info "========================================="

    # Check if running on Proxmox
    if ! command -v pvesh &> /dev/null; then
        error "This script should run on Proxmox host"
        return 1
    fi

    # Validate bridge configuration
    validate_test "vmbr0 exists" "ip link show vmbr0"
    validate_test "vmbr1 exists" "ip link show vmbr1"

    # Validate MTU settings
    validate_test "vmbr0 MTU = 1500" "ip link show vmbr0 | grep -q 'mtu 1500'"
    validate_test "vmbr1 MTU = 1500" "ip link show vmbr1 | grep -q 'mtu 1500'"

    # Validate IP configuration
    validate_test "vmbr0 IP = 192.168.0.2" "ip addr show vmbr0 | grep -q '192.168.0.2/24'"
    validate_test "vmbr1 IP = 10.0.0.2" "ip addr show vmbr1 | grep -q '10.0.0.2/24'"

    # Validate sysctl parameters
    validate_test "IP forwarding enabled" "[ $(sysctl -n net.ipv4.ip_forward) -eq 1 ]"
    validate_test "rp_filter = 2 (loose mode)" "[ $(sysctl -n net.ipv4.conf.all.rp_filter) -eq 2 ]"
    validate_test "bridge-nf-call-iptables enabled" "[ $(sysctl -n net.bridge.bridge-nf-call-iptables) -eq 1 ]"

    # Validate dnsmasq configuration
    if [ -f /etc/dnsmasq.d/detectviz.conf ]; then
        validate_test "dnsmasq config exists" "true"
        validate_test "cluster.internal domain configured" "grep -q 'cluster.internal' /etc/dnsmasq.d/detectviz.conf"
    else
        error "dnsmasq config not found"
    fi

    success "Proxmox host validation completed"
}

validate_vms() {
    info "========================================="
    info "Validating VM Network Configuration"
    info "========================================="

    local nodes=("192.168.0.11" "192.168.0.12" "192.168.0.13" "192.168.0.14")
    local node_names=("master-1" "master-2" "master-3" "app-worker")
    local internal_ips=("10.0.0.11" "10.0.0.12" "10.0.0.13" "10.0.0.14")

    for i in "${!nodes[@]}"; do
        local external_ip="${nodes[$i]}"
        local internal_ip="${internal_ips[$i]}"
        local node_name="${node_names[$i]}"

        info "Checking node: $node_name ($external_ip)"

        # Check SSH connectivity
        if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no ubuntu@$external_ip "exit" 2>/dev/null; then
            error "Cannot SSH to $node_name ($external_ip)"
            continue
        fi

        # Validate network interfaces
        validate_test "$node_name: eth0 exists" \
            "ssh ubuntu@$external_ip 'ip link show eth0'"

        validate_test "$node_name: eth1 exists" \
            "ssh ubuntu@$external_ip 'ip link show eth1'"

        # Validate IP configuration
        validate_test "$node_name: eth0 IP = $external_ip" \
            "ssh ubuntu@$external_ip 'ip addr show eth0 | grep -q $external_ip'"

        validate_test "$node_name: eth1 IP = $internal_ip" \
            "ssh ubuntu@$external_ip 'ip addr show eth1 | grep -q $internal_ip'"

        # Validate MTU
        validate_test "$node_name: eth0 MTU = 1500" \
            "ssh ubuntu@$external_ip 'ip link show eth0 | grep -q \"mtu 1500\"'"

        validate_test "$node_name: eth1 MTU = 1500" \
            "ssh ubuntu@$external_ip 'ip link show eth1 | grep -q \"mtu 1500\"'"

        # Validate sysctl parameters
        validate_test "$node_name: IP forwarding enabled" \
            "ssh ubuntu@$external_ip '[ \$(sysctl -n net.ipv4.ip_forward) -eq 1 ]'"

        validate_test "$node_name: rp_filter = 2" \
            "ssh ubuntu@$external_ip '[ \$(sysctl -n net.ipv4.conf.all.rp_filter) -eq 2 ]'"

        # Validate /etc/hosts
        validate_test "$node_name: /etc/hosts contains cluster.internal" \
            "ssh ubuntu@$external_ip 'grep -q cluster.internal /etc/hosts'"

        echo ""
    done

    success "VM network validation completed"
}

validate_dns() {
    info "========================================="
    info "Validating DNS Resolution"
    info "========================================="

    # Test from Proxmox host (if available)
    if command -v dig &> /dev/null; then
        # External domain tests
        validate_test "DNS: master-1.detectviz.internal resolves to 192.168.0.11" \
            "dig @192.168.0.2 master-1.detectviz.internal +short | grep -q 192.168.0.11"

        # Cluster domain tests
        validate_test "DNS: master-1.cluster.internal resolves to 10.0.0.11" \
            "dig @192.168.0.2 master-1.cluster.internal +short | grep -q 10.0.0.11"

        validate_test "DNS: app-worker.cluster.internal resolves to 10.0.0.14" \
            "dig @192.168.0.2 app-worker.cluster.internal +short | grep -q 10.0.0.14"
    else
        info "dig command not available, skipping DNS tests"
    fi

    # Test from VMs using getent
    local nodes=("192.168.0.11" "192.168.0.14")
    local node_names=("master-1" "app-worker")

    for i in "${!nodes[@]}"; do
        local ip="${nodes[$i]}"
        local name="${node_names[$i]}"

        validate_test "$name: Can resolve master-1.detectviz.internal" \
            "ssh ubuntu@$ip 'getent hosts master-1.detectviz.internal | grep -q 192.168.0.11'"

        validate_test "$name: Can resolve master-1.cluster.internal" \
            "ssh ubuntu@$ip 'getent hosts master-1.cluster.internal | grep -q 10.0.0.11'"

        validate_test "$name: Can resolve app-worker.cluster.internal" \
            "ssh ubuntu@$ip 'getent hosts app-worker.cluster.internal | grep -q 10.0.0.14'"
    done

    success "DNS validation completed"
}

validate_connectivity() {
    info "========================================="
    info "Validating Network Connectivity"
    info "========================================="

    local nodes=("192.168.0.11" "192.168.0.12" "192.168.0.13" "192.168.0.14")
    local node_names=("master-1" "master-2" "master-3" "app-worker")
    local internal_ips=("10.0.0.11" "10.0.0.12" "10.0.0.13" "10.0.0.14")

    # Test external network connectivity (vmbr0)
    info "Testing external network (vmbr0) connectivity..."
    for i in "${!nodes[@]}"; do
        local external_ip="${nodes[$i]}"
        local node_name="${node_names[$i]}"

        validate_test "Ping $node_name external IP ($external_ip)" \
            "ping -c 2 -W 3 $external_ip"
    done

    # Test internal network connectivity (vmbr1)
    info "Testing internal cluster network (vmbr1) connectivity..."
    for i in "${!nodes[@]}"; do
        local source_ip="${nodes[$i]}"
        local source_name="${node_names[$i]}"
        local target_internal="${internal_ips[0]}"  # Test ping to master-1 internal IP

        if [ "$source_ip" != "${nodes[0]}" ]; then  # Don't test from master-1 to itself
            validate_test "$source_name can ping master-1 internal IP (10.0.0.11)" \
                "ssh ubuntu@$source_ip 'ping -c 2 -W 3 $target_internal'"
        fi
    done

    # Test MTU with large packets
    info "Testing MTU with jumbo frames..."
    validate_test "Jumbo frame test (8972 bytes) to 192.168.0.11" \
        "ping -c 2 -M do -s 8972 192.168.0.11"

    success "Connectivity validation completed"
}

# --- Main ---

main() {
    local run_all=true
    local run_proxmox=false
    local run_vms=false
    local run_dns=false
    local run_connectivity=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --proxmox)
                run_all=false
                run_proxmox=true
                shift
                ;;
            --vms)
                run_all=false
                run_vms=true
                shift
                ;;
            --dns)
                run_all=false
                run_dns=true
                shift
                ;;
            --connectivity)
                run_all=false
                run_connectivity=true
                shift
                ;;
            *)
                echo "Unknown option: $1"
                echo "Usage: $0 [--proxmox|--vms|--dns|--connectivity]"
                exit 1
                ;;
        esac
    done

    info "DetectViz Dual Network Validation Script"
    info "=========================================="
    echo ""

    if [ "$run_all" = true ] || [ "$run_proxmox" = true ]; then
        validate_proxmox_host
        echo ""
    fi

    if [ "$run_all" = true ] || [ "$run_vms" = true ]; then
        validate_vms
        echo ""
    fi

    if [ "$run_all" = true ] || [ "$run_dns" = true ]; then
        validate_dns
        echo ""
    fi

    if [ "$run_all" = true ] || [ "$run_connectivity" = true ]; then
        validate_connectivity
        echo ""
    fi

    success "========================================="
    success "All validations completed!"
    success "========================================="
}

main "$@"
