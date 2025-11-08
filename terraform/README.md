# terraform

Terraform 配置，用於在 Proxmox 上自動化創建 Detectviz 平台所需的 5 台虛擬機。

---

## 架構概覽

本倉庫使用 Terraform 自動化管理 Proxmox 虛擬化平台上的基礎設施，實現聲明式配置和版本控制。

### 核心功能
- 自動化 VM 創建與配置
- 網路設定與 IP 分配
- 儲存資源管理
- SSH 金鑰注入與安全配置
- Ansible inventory 自動生成

### 創建資源
- 3 個 Master 節點（控制平面）
- 2 個 Worker 節點（應用運行）
- Ubuntu 22.04 LTS 作業系統
- 自訂網路配置（192.168.0.0/24）
- NVMe/SSD 混合儲存架構

### 技術棧
- Terraform >= 1.5.0 - IaC 工具
- Proxmox Provider >= 2.9.0 - Proxmox VE API 整合
- Ubuntu 22.04 LTS - 作業系統模板

---

## 快速開始

### 前置需求
- Proxmox VE 8.x 環境
- Terraform >= 1.5.0
- Proxmox API 權限
- Ubuntu 22.04 Cloud-Init 模板已準備

### 基本部署

```bash
# 1. 複製配置範本並填入您的設定
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars  # 填入您的 Proxmox API Token 和其他配置

# 2. 初始化 Terraform
terraform init

# 3. 規劃變更（驗證配置）
terraform plan

# 4. 應用配置（創建 VM）
terraform apply

# 5. 生成 Ansible inventory（用於下游 ansible）
terraform output -json > /tmp/terraform-output.json
```

---

## 檔案結構

```
terraform/
├── main.tf                     # 主配置文件（VM 定義）
├── variables.tf                # 變數定義與驗證
├── outputs.tf                  # 輸出定義（Ansible inventory）
├── terraform.tfvars.example    # 配置範本
├── terraform.tfstate           # 狀態檔案（已 gitignore）
├── .gitignore                  # Git 忽略規則
├── README.md                   # 本文檔
└── docs/                       # 相關文檔
    ├── proxmox-credentials.md  # Proxmox API Token 設定指南
    ├── ubuntu-template.md      # Ubuntu Cloud-Init 模板製作
    └── best-practices.md       # Terraform 最佳實踐與規格
```

### 關鍵檔案說明

#### terraform.tfvars
Terraform 變數配置文件：
- `proxmox_api_token_id`: Proxmox API Token ID
- `proxmox_api_token_secret`: Proxmox API Token Secret
- `ssh_private_key_path`: SSH 私鑰路徑（預設 `~/.ssh/id_rsa`）

⚠️ **安全提醒**: 複製 `terraform.tfvars.example` 並填入真實值，此檔案不會被提交到 Git

#### terraform.tfvars.example
定義所有必要變數的範例配置：
- Proxmox 連接資訊（API URL、Token）
- VM 規格（CPU、記憶體、磁碟）
- 網路配置（IP 範圍、閘道）
- SSH 金鑰路徑

#### outputs.tf
生成 Ansible inventory 所需的結構化輸出：
- 節點 IP 地址
- SSH 連接資訊
- 節點角色（master/worker）

---

## 配置說明

### 必要變數

| 變數名稱 | 說明 | 範例值 |
|---------|------|--------|
| `proxmox_api_url` | Proxmox API 端點 | `https://192.168.0.5:8006/api2/json` |
| `proxmox_api_token_id` | API Token ID | `terraform@pam!terraform` |
| `proxmox_api_token_secret` | API Token Secret | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `ssh_public_key` | SSH 公鑰內容 | `ssh-rsa AAAAB3...` |

### VM 規格配置

#### Master 節點
```hcl
master_count  = 3
master_cpu    = 4
master_memory = 8192  # MB
master_disk   = 50    # GB
```

#### Worker 節點
```hcl
worker_count  = 2
worker_cpu    = 8
worker_memory = 16384
worker_disk   = 100
```

---

## 進階操作

### 僅規劃不執行
```bash
terraform plan -var-file=terraform.tfvars
```

### 查看當前狀態
```bash
terraform show
```

### 僅創建特定資源
```bash
terraform apply -target=proxmox_vm_qemu.master[0]
```

### 銷毀所有資源
```bash
terraform destroy -var-file=terraform.tfvars
```

### 刷新狀態
```bash
terraform refresh
```

---

## 故障排除

### 常見問題

#### 1. API 連接失敗
```
Error: error creating VM: 401 Permission check failed
```

**解決方案**：
- 檢查 Proxmox API Token 權限
- 確認 Token 未過期
- 驗證 API URL 格式正確

#### 2. Cloud-Init 模板不存在
```
Error: VM template not found
```

**解決方案**：
- 確認已按照 Proxmox 文檔創建 Ubuntu 22.04 Cloud-Init 模板
- 檢查模板 ID 是否正確（通常為 9000）

#### 3. 資源已存在
```
Error: resource already exists
```

**解決方案**：
```bash
# 導入現有資源到 Terraform 狀態
terraform import proxmox_vm_qemu.master[0] <proxmox-vm-id>
```

---

## 參考資源

### Terraform 文檔
- [Terraform 官方文檔](https://developer.hashicorp.com/terraform/docs)
- [Terraform CLI 命令](https://developer.hashicorp.com/terraform/cli)
- [Terraform 狀態管理](https://developer.hashicorp.com/terraform/language/state)

### Proxmox 文檔
- [Proxmox VE 文檔](https://pve.proxmox.com/pve-docs/)
- [Proxmox API 文檔](https://pve.proxmox.com/pve-docs/api-viewer/)
- [Proxmox Cloud-Init 支援](https://pve.proxmox.com/wiki/Cloud-Init_Support)

### Provider 文檔
- [Proxmox Provider 文檔](https://registry.terraform.io/providers/Telmate/proxmox/latest/docs)
- [Proxmox Provider GitHub](https://github.com/Telmate/terraform-provider-proxmox)

### 本倉庫文檔
- [Proxmox API 認證設定](docs/proxmox-credentials.md)
- [Ubuntu Cloud-Init 模板製作](docs/ubuntu-template.md)
- [Terraform 最佳實踐與規格](docs/best-practices.md)

---

## 相關倉庫

| 倉庫 | 描述 | 依賴關係 |
|------|------|----------|
| [infra-deployment](https://github.com/detectviz/infra-deployment) | 中央編排與部署流程 | 調度 terraform |
| [ansible](https://github.com/detectviz/ansible) | Kubernetes 集群部署 | 使用 Terraform 輸出作為 inventory |
| [kubernetes](https://github.com/detectviz/kubernetes) | 集群級別配置 | 在 Terraform 建立的 VM 上運行 |
| [gitops-argocd](https://github.com/detectviz/gitops-argocd) | GitOps 應用交付 | 最終應用部署 |
| [observability-stack](https://github.com/detectviz/observability-stack) | 可觀測性外部組件 | 基礎設施監控 |

> 📌 **完整架構說明**: 請參閱 [https://github.com/detectviz/infra-deployment/blob/main/docs/ARCHITECTURE.md](https://github.com/detectviz/infra-deployment/blob/main/docs/ARCHITECTURE.md) - 五倉庫職責劃分與資料流總覽

---

## 維護資訊

### 聯絡方式
- 維護者: Detectviz Team
- 問題回報: [GitHub Issues](https://github.com/detectviz/terraform/issues)

### 版本資訊
- 本倉庫版本: v2.0.0
- Terraform 版本: >= 1.5.0
- Proxmox Provider 版本: >= 2.9.0
- Ubuntu 版本: 22.04 LTS
- 相依倉庫:
  - infra-deployment >= v2.0.0
- 最後更新: 2025-10-25
