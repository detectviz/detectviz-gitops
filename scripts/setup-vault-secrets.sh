#!/bin/bash
set -e

# DetectViz Platform - Vault Secrets Setup Script
# 設置必要的 secrets 到 Vault 中供 External Secrets Operator 使用

echo "🔐 DetectViz Platform - Vault Secrets 設置腳本"
echo "================================================"

# 檢查必要的工具
command -v vault >/dev/null 2>&1 || { echo "❌ 需要安裝 vault CLI"; exit 1; }

# 檢查 SSH 金鑰檔案是否存在
SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/id_ed25519_detectviz}"
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "❌ 找不到 SSH 私鑰檔案: $SSH_KEY_PATH"
    echo "請設置 SSH_KEY_PATH 環境變數指向正確的私鑰檔案"
    exit 1
fi

echo "✅ 找到 SSH 私鑰檔案: $SSH_KEY_PATH"

# 將 SSH 私鑰存儲到 Vault
echo "📤 將 SSH 私鑰存儲到 Vault..."
vault kv put secret/argocd/repo-ssh-key private_key="$(cat "$SSH_KEY_PATH")"

echo "✅ SSH 私鑰已安全存儲到 Vault: secret/argocd/repo-ssh-key"
echo ""
echo "📋 下一步："
echo "1. 確保 Vault 已正確配置並運行"
echo "2. 確保 External Secrets Operator 已部署"
echo "3. ArgoCD 部署時會自動通過 ESO 獲取 SSH 金鑰"
echo ""
echo "🔒 安全提醒："
echo "- SSH 私鑰已加密存儲在 Vault 中，不會明碼存放在 Git 中"
echo "- 確保 Vault 的訪問權限正確配置"
