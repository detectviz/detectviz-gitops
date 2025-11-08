#!/bin/bash

# vm-1 網路週期性凍結診斷腳本
# 用於診斷 vm-1 與 Proxmox 主機之間的週期性連線問題

set -e

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

VM1_IP="192.168.0.11"
PROXMOX_IP="192.168.0.1"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}vm-1 網路診斷腳本${NC}"
echo -e "${BLUE}========================================${NC}"
echo

# 1. 測試從工作站到 vm-1 的連通性
echo -e "${YELLOW}[1/6] 測試從工作站到 vm-1 的連通性...${NC}"
if ping -c 3 -W 5 $VM1_IP > /dev/null 2>&1; then
    echo -e "${GREEN}✓ 工作站 -> vm-1 連通正常${NC}"
else
    echo -e "${RED}✗ 工作站無法 ping 通 vm-1${NC}"
    exit 1
fi
echo

# 2. 測試 vm-1 到 Proxmox 主機的連通性（長時間監控）
echo -e "${YELLOW}[2/6] 測試 vm-1 到 Proxmox 的連通性（60秒監控，觀察是否有丟包）...${NC}"
echo -e "${BLUE}按 Ctrl+C 可提前結束...${NC}"
ssh -o StrictHostKeyChecking=no -i $SSH_KEY ubuntu@$VM1_IP "timeout 60 ping -i 1 $PROXMOX_IP 2>&1 | tee /tmp/ping-test.log" || true

# 分析 ping 結果
echo -e "\n${YELLOW}分析 ping 結果...${NC}"
ssh -i $SSH_KEY ubuntu@$VM1_IP "cat /tmp/ping-test.log | tail -20"
echo

# 3. 檢查 vm-1 網卡狀態和統計
echo -e "${YELLOW}[3/6] 檢查 vm-1 網卡狀態...${NC}"
ssh -i $SSH_KEY ubuntu@$VM1_IP "ip -s link show eth0"
echo

# 4. 檢查 vm-1 網卡驅動和設定
echo -e "${YELLOW}[4/6] 檢查 vm-1 網卡驅動資訊...${NC}"
ssh -i $SSH_KEY ubuntu@$VM1_IP "sudo ethtool eth0 2>/dev/null || echo 'ethtool not installed'"
echo

# 5. 檢查 vm-1 網路緩衝區和隊列
echo -e "${YELLOW}[5/6] 檢查網路緩衝區設定...${NC}"
ssh -i $SSH_KEY ubuntu@$VM1_IP "sudo ethtool -g eth0 2>/dev/null || echo 'ethtool not installed'"
echo

# 6. 檢查系統日誌中的網路錯誤
echo -e "${YELLOW}[6/6] 檢查系統日誌中的網路錯誤...${NC}"
ssh -i $SSH_KEY ubuntu@$VM1_IP "sudo journalctl -u networking -n 50 --no-pager | grep -i error || echo 'No errors found'"
ssh -i $SSH_KEY ubuntu@$VM1_IP "sudo dmesg | grep -i 'eth0\|virtio' | tail -20 || echo 'No dmesg entries'"
echo

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}診斷完成${NC}"
echo -e "${BLUE}========================================${NC}"
echo
echo -e "${YELLOW}建議的 Proxmox 端檢查步驟：${NC}"
echo
echo -e "1. 檢查 vm-1 的網卡模型設定："
echo -e "   ${GREEN}在 Proxmox Shell 執行：${NC}"
echo -e "   qm config <vm-1-id> | grep net"
echo
echo -e "2. 檢查 vmbr0 bridge 設定："
echo -e "   ${GREEN}在 Proxmox Shell 執行：${NC}"
echo -e "   cat /etc/network/interfaces | grep -A 10 vmbr0"
echo
echo -e "3. 檢查 bridge 的 STP 狀態："
echo -e "   ${GREEN}在 Proxmox Shell 執行：${NC}"
echo -e "   brctl show vmbr0"
echo -e "   brctl showstp vmbr0"
echo
echo -e "4. 檢查 vm-1 的 tap 介面狀態："
echo -e "   ${GREEN}在 Proxmox Shell 執行：${NC}"
echo -e "   ip -s link show | grep -A 5 tap"
echo
echo -e "${YELLOW}可能的修復方案：${NC}"
echo -e "- 方案 1: 將 vm-1 網卡從 VirtIO 改為 Intel E1000"
echo -e "- 方案 2: 調整 VirtIO 隊列大小"
echo -e "- 方案 3: 禁用 Bridge STP（如果啟用）"
echo -e "- 方案 4: 調整 vm-1 的網路延遲設定"
