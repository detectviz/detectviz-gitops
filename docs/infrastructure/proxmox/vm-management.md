# Proxmox VM 管理指南

## 概述

本指南說明在 Proxmox VE 中管理虛擬機的最佳實踐，包括 QEMU Guest Agent 安裝、VM 優化和維護。

## VM 創建最佳實踐

### 1. VM 命名慣例

DetectViz 集群使用以下命名慣例：
- Master 節點：`master-1`, `master-2`, `master-3`
- Worker 節點：`app-worker`

### 2. VM 資源配置

根據 [README.md](../../README.md) 的規格配置：

#### Master 節點
- CPU：4 核 (master-1), 3 核 (master-2/3)
- 記憶體：8 GB
- 儲存：100 GB (系統碟)

#### Worker 節點
- CPU：12 核
- 記憶體：24 GB
- 儲存：320 GB (系統碟)

### 3. 網路配置

- Bridge：`vmbr0`
- Model：`VirtIO`
- 啟用：Hardware checks, Firewall

## QEMU Guest Agent 安裝

### 為什麼需要 QEMU Guest Agent？

QEMU Guest Agent 提供 VM 內部資訊給 Proxmox 主機，提升管理效能和監控能力。

### 在 VM 中安裝

#### 1. 更新系統並安裝
```bash
sudo apt-get update
sudo apt-get install qemu-guest-agent
```

#### 2. 啟動並設定開機自動啟動
```bash
sudo systemctl enable qemu-guest-agent
sudo systemctl start qemu-guest-agent
```

#### 3. 檢查服務狀態
```bash
sudo systemctl status qemu-guest-agent
```

> **注意：** 安裝完成後，建議重新啟動 VM 以確保 agent 正確載入。

### Proxmox Web UI 驗證

安裝 QEMU Guest Agent 後，在 Proxmox Web UI 的 VM 摘要頁面會顯示更多系統資訊：

- ✅ 精確的 CPU 使用率
- ✅ 記憶體使用詳情
- ✅ 網路流量統計
- ✅ 磁碟 I/O 資訊

## VM 優化設置

### 1. CPU 優化

- **CPU Type**：`host` (透傳主機 CPU 特性)
- **CPU Limit**：根據需求設置
- **CPU Units**：1024 (預設公平分享)

### 2. 記憶體優化

- **Memory**：dedicated 記憶體
- **Ballooning**：啟用動態調整
- **Hugepages**：視需求啟用

### 3. 儲存優化

- **Disk Bus**：SCSI (效能最佳)
- **Cache**：Write back
- **Discard**：啟用 TRIM 支持
- **SSD emulation**：啟用

### 4. 網路優化

- **Model**：VirtIO
- **Firewall**：啟用
- **Multiqueue**：多 CPU 時啟用

## VM 維護任務

### 定期備份

```bash
# 使用 Proxmox Backup Server 或其他備份方案
# 建議每日備份重要 VM
```

### 效能監控

- 使用 Proxmox Web UI 監控
- 檢查 CPU/記憶體/網路使用率
- 監控儲存 I/O 效能

### 資源調整

根據實際使用情況調整資源：
- CPU 核心數
- 記憶體大小
- 儲存空間

## 故障排除

### 常見問題

#### VM 無法啟動
- 檢查儲存空間是否足夠
- 確認網路配置正確
- 查看 Proxmox 日誌

#### 網路連線問題
- 檢查 Bridge 配置
- 確認防火牆規則
- 驗證 VM 內網路設置

#### 效能問題
- 檢查資源分配
- 監控系統負載
- 優化儲存配置

## 自動化部署

DetectViz 使用 Terraform 自動化 VM 部署：

```bash
cd terraform
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

詳見：[Terraform 配置指南](../../terraform/README.md)

## 下一步

- [Ansible 自動化部署](../../ansible/README.md)
- [Kubernetes 集群初始化](../../README.md#deployment)
