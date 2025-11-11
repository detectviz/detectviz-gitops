#!/bin/bash
# 清理 Terraform 創建失敗的 VM
# 用途：刪除 Proxmox 上的殘留 VM 和 Terraform 狀態

set -e

echo "🧹 清理失敗的 VM 部署"
echo "================================================"

# 檢查是否在 terraform 目錄
if [ ! -f "main.tf" ]; then
    echo "❌ 錯誤：請在 terraform 目錄下執行此腳本"
    exit 1
fi

# 1. 清理 Terraform 狀態中的錯誤資源
echo ""
echo "📋 步驟 1: 檢查 Terraform 狀態..."
if [ -f "terraform.tfstate" ]; then
    echo "找到 terraform.tfstate，顯示當前資源："
    terraform state list || true

    echo ""
    read -p "是否要清空 Terraform 狀態？這將移除所有追蹤的資源 (y/N): " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        echo "⚠️  備份當前狀態..."
        cp terraform.tfstate terraform.tfstate.backup.$(date +%Y%m%d_%H%M%S)

        echo "🗑️  清空 Terraform 狀態..."
        rm -f terraform.tfstate terraform.tfstate.backup
        echo "✅ Terraform 狀態已清空"
    fi
else
    echo "沒有找到 terraform.tfstate"
fi

# 2. 提示手動清理 Proxmox VM
echo ""
echo "================================================"
echo "📋 步驟 2: 清理 Proxmox 上的 VM"
echo "================================================"
echo ""
echo "請在 Proxmox Web UI 或使用以下命令手動刪除失敗的 VM："
echo ""
echo "方法 1: Proxmox Web UI"
echo "  1. 登入 https://192.168.0.2:8006"
echo "  2. 選擇失敗的 VM (VM 111-114):"
echo "    - 111: master-1"
echo "    - 112: master-2"
echo "    - 113: master-3"
echo "    - 114: app-worker"
echo "  3. 停止 VM (如果正在運行)"
echo "  4. 右鍵 -> 刪除"
echo ""
echo "方法 2: SSH 到 Proxmox 節點執行"
echo "  ssh root@192.168.0.2"
echo "  qm stop 111 && qm destroy 111  # master-1"
echo "  qm stop 112 && qm destroy 112  # master-2"
echo "  qm stop 113 && qm destroy 113  # master-3"
echo "  qm stop 114 && qm destroy 114  # app-worker"
echo ""
echo "方法 3: 使用 pvesh API"
echo "  pvesh delete /nodes/proxmox/qemu/111  # master-1"
echo "  pvesh delete /nodes/proxmox/qemu/112  # master-2"
echo "  pvesh delete /nodes/proxmox/qemu/113  # master-3"
echo "  pvesh delete /nodes/proxmox/qemu/114  # app-worker"
echo ""

read -p "已清理 Proxmox 上的 VM？(y/N): " cleaned
if [ "$cleaned" != "y" ] && [ "$cleaned" != "Y" ]; then
    echo "⚠️  請先清理 Proxmox VM 再繼續"
    exit 1
fi

# 3. 驗證清理結果
echo ""
echo "✅ 清理完成！"
echo ""
echo "下一步："
echo "  1. 驗證配置: terraform validate"
echo "  2. 查看計畫: terraform plan -var-file=terraform.tfvars"
echo "  3. 重新部署: terraform apply -var-file=terraform.tfvars"
echo ""
