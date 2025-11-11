#!/bin/bash
set -e

echo "🔄 DetectViz Platform - 集群清理與重新部署腳本"
echo "=============================================="

# 檢查 terraform.tfvars 檔案是否存在
if [ ! -f "terraform.tfvars" ]; then
    echo "❌ 錯誤：找不到 terraform.tfvars 檔案"
    echo "請複製 terraform.tfvars.example 並填入您的配置："
    echo "  cp terraform.tfvars.example terraform.tfvars"
    echo "然後編輯 terraform.tfvars 檔案，設定您的 Proxmox API Token"
    exit 1
fi

echo "✅ 找到 terraform.tfvars 配置文件"

# 銷毀現有資源
echo "🗑️  銷毀現有資源..."
terraform destroy -auto-approve

# 重新初始化並部署
echo "🚀 重新部署基礎設施..."
terraform init
terraform plan
terraform apply -auto-approve

echo "✅ 基礎設施部署完成！"
echo "📋 下一步："
echo "1. 檢查 VM 狀態：terraform output"
echo "2. 測試 SSH 連接：ssh ubuntu@192.168.0.11"
echo "3. 繼續部署：參考 deploy-guide.md 的 Phase 2"
