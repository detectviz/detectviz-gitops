# DetectViz 基礎設施文檔

## 概述

本目錄包含 DetectViz 平臺的完整基礎設施設置文檔，按照功能模塊進行組織，便於查找和維護。

## 目錄結構

```
docs/infrastructure/
├── README.md                 # 本文件
├── proxmox/                  # Proxmox VE 虛擬化平台
│   ├── installation.md       # Proxmox 安裝指南
│   ├── configuration.md      # Proxmox 配置和優化
│   └── vm-management.md      # VM 管理最佳實踐
├── hardware/                 # 硬體管理 (KVM/IPMI)
│   ├── ipmi-setup.md         # IPMI/KVM 管理設置
│   ├── bios-config.md        # BIOS 和硬體配置
│   └── hardware-specs.md     # 硬體規格說明
├── networking/               # 網路配置
│   ├── bridge-config.md      # Proxmox Bridge 配置
│   ├── dns-setup.md          # DNS 伺服器設置
│   ├── network-optimization.md # 網路優化 (rp_filter等)
│   └── domain-mapping.md     # 域名映射參考
└── storage/                  # 儲存配置
    ├── storage-architecture.md # 儲存架構設計
    └── storage-setup.md      # 儲存設置指南
```

## 職責劃分

### Proxmox 虛擬化平台 (`proxmox/`)
專注於 Proxmox VE 的安裝、配置和虛擬機管理：
- **安裝和初始化**
- **系統配置和優化**
- **VM 創建和管理**
- **QEMU Guest Agent 設置**

### 硬體管理 (`hardware/`)
處理底層硬體和 IPMI 管理：
- **IPMI/KVM 遠端管理**
- **BIOS 設置和硬體初始化**
- **硬體規格和維護**
- **電源和冷卻管理**

### 網路配置 (`networking/`)
涵蓋所有網路相關設置：
- **Bridge 網路配置**
- **DNS 伺服器和域名解析**
- **網路性能優化**
- **域名映射和服務發現**

### 儲存配置 (`storage/`)
管理儲存架構和設置：
- **混合儲存架構設計**
- **LVM 和檔案系統配置**
- **效能優化和容量規劃**
- **備份策略**

## 部署順序

### 1. 硬體準備階段
1. [硬體規格確認](hardware/hardware-specs.md)
2. [BIOS 配置](hardware/bios-config.md)
3. [IPMI 設置](hardware/ipmi-setup.md)

### 2. Proxmox 安裝階段
1. [Proxmox 安裝](proxmox/installation.md)
2. [Proxmox 配置](proxmox/configuration.md)

### 3. 基礎設施配置階段
1. [網路設置](networking/bridge-config.md)
2. [DNS 配置](networking/dns-setup.md)
3. [儲存設置](storage/storage-setup.md)

### 4. VM 部署階段
1. [VM 管理](proxmox/vm-management.md)
2. Terraform 自動化部署

## 關鍵配置參考

### IP 分配
| 組件 | IP 位址 | 說明 |
|------|---------|------|
| Proxmox | 192.168.0.2 | 虛擬化平台 |
| IPMI | 192.168.0.104 | 硬體管理 |
| K8s VIP | 192.168.0.10 | 集群 API |
| Master 節點 | 192.168.0.11-13 | 控制平面 |
| Worker 節點 | 192.168.0.14 | 應用運行 |

### 域名映射
| 服務 | 域名 | IP 位址 |
|------|------|---------|
| Proxmox | proxmox.detectviz.internal | 192.168.0.2 |
| Kubernetes API | k8s-api.detectviz.internal | 192.168.0.10 |
| ArgoCD | argocd.detectviz.local | 192.168.0.10 |

### 儲存架構
| 層級 | 設備 | 容量 | 用途 |
|------|------|------|------|
| 系統層 | SATA SSD | 512GB | Proxmox 系統 |
| 高效層 | NVMe SSD | 2TB | VM 和應用資料 |
| 備份層 | SATA 分區 | 200GB+ | 備份儲存 |

## 維護和更新

### 定期檢查
- 硬體健康狀態
- 網路連線和 DNS 解析
- 儲存使用率和性能
- 備份完整性

### 配置變更
1. 更新相關文檔
2. 測試配置變更
3. 更新 DNS 和網路配置
4. 驗證服務可用性

## 故障排除

### 快速診斷檢查表
- [ ] 硬體電源和連線正常
- [ ] IPMI 遠端管理可訪問
- [ ] Proxmox Web UI 可訪問
- [ ] 網路橋接配置正確
- [ ] DNS 解析正常
- [ ] 儲存空間充足

### 常見問題
- 網路連線問題：檢查 [網路優化指南](networking/network-optimization.md)
- 儲存性能問題：參考 [儲存架構設計](storage/storage-architecture.md)
- VM 管理問題：查看 [VM 管理指南](proxmox/vm-management.md)

## 相關項目

- [Terraform 配置](../../terraform/) - 基礎設施即代碼
- [Ansible 配置](../../ansible/) - 自動化部署
- [ArgoCD 配置](../../argocd/) - GitOps 應用交付
- [主 README](../../README.md) - 總體項目說明