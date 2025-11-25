# detectviz-gitops

[![Terraform](https://img.shields.io/badge/Terraform-%235835CC.svg?logo=terraform&logoColor=white)](https://www.terraform.io/)
[![Ansible](https://img.shields.io/badge/Ansible-%231A1918.svg?logo=ansible&logoColor=white)](https://www.ansible.com/)
[![ArgoCD](https://img.shields.io/badge/ArgoCD-orange?logo=argo&logoColor=white)](https://argo-cd.readthedocs.io/)
![Commits](https://img.shields.io/badge/commits-lost--count-blueviolet)
![Status](https://img.shields.io/badge/status-stable-green)

> [!INFO]
> 本專案設計以展示用途為主，重視服務分佈與觀測整合，不強調效能壓測或高負載支撐能力做過度設計。

Detectviz Infra 採用多層自動化堆疊實現完整基礎設施管理。底層使用 KVM 與 Proxmox 作為虛擬化平台，Terraform 負責 VM 的宣告式建立，Ansible 用於 VM 的設定與 Kubernetes 安裝。接著透過 Argo CD 實現 GitOps 控制面，並以 Helm 部署 Kubernetes 應用。整體流程如下：

```bash
KVM/Proxmox
    ↓
[P1]Terraform (VM 建立)
    ↓
[P2]Ansible (Kubernetes 安裝)
    ↓
[P3]Argo CD (GitOps 啟動)
    ↓
[P4]Helm (Infrastructure Namespace)
    ↓
[P5]Helm (Application Namespace)
```

此專案為 Detectviz 平台的基礎層，用於建構 Kubernetes 環境與 GitOps 控制面。

```mermaid
graph LR
  subgraph ControlPlane
    VM1[master-1<br/>4C/8GB/100GB<br/>Prometheus]
    VM2[master-2<br/>3C/8GB/100GB<br/>Mimir]
    VM3[master-3<br/>3C/8GB/100GB<br/>Loki]
  end

  subgraph Worker
    VM4[app-worker<br/>12C/24GB<br/>System: 100GB + Data: 250GB<br/>Argo CD, Keycloak<br/>Grafana, Tempo<br/>PostgreSQL, Vault]
  end

  VM1 -->|API Server| VM4
  VM2 -->|Metric Read| VM4
  VM3 -->|Log Query| VM4
```

## infra 服務列表 (detectviz-gitops)
對應部署階段：[P2] ~ [P4]
- [P2] **kube-vip**：控制平面高可用 (VIP 192.168.0.10，L2 ARP 模式)
- [P2] **calico**：CNI 網路插件 (VXLAN mode，NetworkPolicy enforcement，MTU 1450)
- [P3] **argocd**：GitOps 控制面與應用交付 (HA 模式，Redis HA)
- [P3] **vault**：秘密管理與安全存儲 (Raft 儲存後端)
- [P3] **cert-manager**：TLS 證書自動化管理 (Self-signed ClusterIssuer)
- [P3] **external-secrets-operator**：從 Vault 同步秘密至 Kubernetes Secret
- [P4] **metallb**：LoadBalancer 服務提供 (L2 模式，IP Pool 192.168.0.200-220)
- [P4] **topolvm**：本地儲存 Volume 管理 (LVM-based CSI driver，app-worker data-vg: 250GB)
- [P4] **ingress-nginx**：L7 反向代理與 Ingress Controller (VIP 192.168.0.10)

> [!NOTE]
> Kubernetes 預設系統元件（如：`coredns`, `kube-controller-manager`, `kube-scheduler`, `kube-proxy`）由 Ansible 安裝時一併建立，雖不經 Helm 管理，仍為 Control Plane 基礎組件。

## apps 服務列表
對應部署階段：[P5]

### Platform Services (獨立 namespace)
- [P5] **postgresql**：資料庫服務 (Grafana / Keycloak backend，HA 3 replicas)
- [P5] **pgbouncer-hpa**：PostgreSQL 連線池 + HPA，自動調整連線代理副本 (namespace: postgresql)
- [P5] **keycloak**：OIDC 身份與存取控制 (Realm-based multi-tenancy)

### Application Layer
- [P5] **grafana**：可觀測性與視覺化介面 (HA 2 replicas，PostgreSQL backend)

### Observability Backend (monitoring namespace)
- [P5] **prometheus**：指標收集與查詢 (2 replicas，15天 retention)
- [P5] **loki**：日誌收集與查詢後端 (TSDB v13，30天 retention)
- [P5] **tempo**：追蹤資料收集與分析 (OTLP receivers，30天 retention)
- [P5] **mimir**：長期指標儲存 (S3/Minio backend，HA 2 replicas)
- [P5] **minio**：S3-compatible 物件儲存 (Mimir blocks/ruler/alertmanager)
- [P5] **alloy**：統一收集 log、metrics、trace 的代理元件 (DaemonSet，取代 node-exporter)
- [P5] **alertmanager**：告警通知與規則管理 (3 replicas)

### ApplicationSet 與 overlay 入口
為符合《DetectViz Platform Constitution》對 base/overlay 分離的要求，`apps-appset` 會直接載入各應用的 overlay 目錄：

| Application | ApplicationSet `spec.generators.list[].path` |
|-------------|----------------------------------------------|
| postgresql (production) | `argocd/apps/observability/postgresql/overlays/production` |
| keycloak | `argocd/apps/identity/keycloak/overlays/production` |
| pgbouncer-hpa | `argocd/apps/observability/pgbouncer-hpa/overlays/production` |
| grafana | `argocd/apps/observability/grafana/overlays/production` |
| prometheus | `argocd/apps/observability/prometheus/overlays/production` |
| loki | `argocd/apps/observability/loki/overlays/production` |
| tempo | `argocd/apps/observability/tempo/overlays/production` |
| mimir | `argocd/apps/observability/mimir/overlays/production` |
| minio | `argocd/apps/observability/minio/overlays/production` |
| alloy | `argocd/apps/observability/alloy/overlays/production` |
| alertmanager | `argocd/apps/observability/alertmanager/overlays/production` |

> [!TIP]
> 新增觀測類或身分服務時，請先建立 `base/` 與 `overlays/`，並讓 ApplicationSet 指向 overlay 路徑，以避免 Argo CD 生成空白 manifests。

#### PostgreSQL overlay profiles

- `overlays/production`：預設由 ApplicationSet 掛載，提供 `pgpool` 2 副本 + `postgresql` 3 副本、TopoLVM 永久磁碟（10Gi/Replica）與啟用 ServiceMonitor。
- `overlays/test`：僅用於短期功能驗證，內容參照 `values.test.yaml`（單副本、關閉 PVC 與 ServiceMonitor）。

若需在 CI/臨時環境使用測試 profile，請：

1. 將 `apps-appset` 中 `postgresql` 的 `path` 暫時改為 `argocd/apps/observability/postgresql/overlays/test`。
2. 執行 `kustomize build --enable-helm argocd/apps/observability/postgresql/overlays/test` 確認生成 manifests。
3. 完成測試後恢復 `path` 為 `.../overlays/production`，並再次同步 PostgreSQL 應用。

### Infrastructure ApplicationSet 入口
`infra-appset` 使用 Git Generator 掃描 `argocd/apps/infrastructure/*`。為了在維持原有路徑的前提下載入 overlay（Helm values、ExternalSecret、patches），每個基礎設施目錄都新增了根層 `kustomization.yaml`，內容只有 `resources: - overlays` 與命名空間宣告：

| 應用 | ApplicationSet 入口 | overlay 來源 |
|------|---------------------|--------------|
| infra-argocd | `argocd/apps/infrastructure/argocd` | `argocd/apps/infrastructure/argocd/overlays/production` |
| infra-cert-manager | `argocd/apps/infrastructure/cert-manager` | `argocd/apps/infrastructure/cert-manager/overlays/production` |
| infra-external-secrets-operator | `argocd/apps/infrastructure/external-secrets-operator` | `argocd/apps/infrastructure/external-secrets-operator/overlays/production` |
| infra-ingress-nginx | `argocd/apps/infrastructure/ingress-nginx` | `argocd/apps/infrastructure/ingress-nginx/overlays/production` |
| infra-kube-vip | `argocd/apps/infrastructure/kube-vip` | `argocd/apps/infrastructure/kube-vip/overlays/production` |
| infra-local-path-provisioner | `argocd/apps/infrastructure/local-path-provisioner` | `argocd/apps/infrastructure/local-path-provisioner/overlays/production` |
| infra-metallb | `argocd/apps/infrastructure/metallb` | `argocd/apps/infrastructure/metallb/overlays/production` |
| infra-topolvm | `argocd/apps/infrastructure/topolvm` | `argocd/apps/infrastructure/topolvm/overlays/production` |
| infra-vault | `argocd/apps/infrastructure/vault` | `argocd/apps/infrastructure/vault/overlays/production` |

> 註：`infra-appset` 會自動為每個應用程式名稱添加 `infra-` 前綴 (例如: `infra-argocd`, `infra-vault`)。

> 在新增基礎設施元件時，請複製同樣的結構，並執行 `kustomize build --enable-helm argocd/apps/infrastructure/<component>` 驗證根層入口確實載入 overlay。若 Helm Chart 需要存取外部網路而環境受限，請在 PR 測試結果中紀錄替代驗證方式。

## Grafana 預設整合
為強化展示一致性，Grafana 透過 Helm 的自動化設定預設載入以下元件：
- **Datasource Provisioning**：
  - Mimir（long-term metrics，default datasource）
  - Loki（logs）
  - Tempo（traces）
  - Alertmanager（alerts）

- **Dashboard Provisioning** (ConfigMap-based GitOps)：
  - 3-folder structure: Platform, Infrastructure, Applications
  - Kubernetes Cluster Overview (nodes, pods, CPU, memory)
  - 文檔: `argocd/apps/observability/grafana/overlays/production/dashboards/README.md`

## 目錄結構
```bash
detectviz-gitops/
├── bootstrap/                 # 集群級別引導資源
│   ├── argocd-projects.yaml   # ArgoCD AppProjects
│   ├── cluster-resources/     # Namespaces + 證書 + 擴展
│   └── README.md
├── apps/
│   ├── identity/
│   │   └── ...
│   ├── infrastructure/
│   │   ├── argocd/            # ArgoCD namespace-level 資源
│   │   └── ...
│   └── observability/
│       └── ...   
├── appsets/                       # ApplicationSets
│   ├── argocd-bootstrap-app.yaml  # ArgoCD + 集群資源引導
│   ├── infra-appset.yaml          # detectviz-apps/infra/
│   └── apps-appset.yaml           # detectviz-apps/apps/
├── root-argocd-app.yaml           # App-of-Apps
└── README.md
```

## 前置作業（一次性手動設置）

以下為 Detectviz 平台初始建置前的必要準備作業：

### 安全性設置

#### 1. SSH 金鑰建立與發佈
- 產生 SSH 金鑰對：`ssh-keygen -t rsa -b 4096`
- 公鑰將由 Terraform 注入至 VM 的 Cloud-Init 配置

#### 2. Secrets 管理規劃
| 類型 | 來源 | 儲存位置 |
|------|------|----------|
| Vault Root Token | `vault operator init` | Bitwarden / 1Password |
| Argo CD Admin 密碼 | `argocd-initial-admin-secret` | `secrets/argocd.md` |
| Terraform 變數 | `terraform.tfvars` | 本地 `.secrets/` 目錄 |
| SSH 私鑰 | `~/.ssh/id_rsa` | 本機（勿入 Git） |

### Proxmox 環境準備

#### 3. Proxmox 基礎配置
- **主機 IP**: 192.168.0.2
- **API Token**: 生成並記錄 Token ID/Secret
- **節點名稱**: proxmox
- **Ubuntu 模板**: ubuntu-2204-template

#### 4. Ubuntu Cloud-Init 模板
- 匯入 Ubuntu 22.04 Cloud Image
- 啟用 Cloud-Init 並設定：
  - Serial Console 啟用
  - VirtIO 網路介面 + vmbr0 橋接器
  - 安裝 qemu-guest-agent
  - Cloud-Init 自動啟動

### 網路配置

#### 5. Proxmox Host 網路設定
參考：`docs/infrastructure/networking/network-info.md`

### 🛠️ 可選工具準備

#### 6. 本機工具安裝
- kubectl (Kubernetes CLI)
- helm (包管理工具)
- argocd CLI (GitOps 操作)

#### 7. DNS Provider 設定（如使用外部域名）
- Cloudflare API Token (zone:edit 權限)
- 記錄於 `secrets/cert-manager.md`

> [!IMPORTANT]
> 上述設定為一次性初始化作業。敏感資訊請勿提交至 Git 版本控管。

## 部署流程摘要

```mermaid
graph TD
    A[前置作業] --> B[Terraform VM 建立]
    B --> C[Ansible Kubernetes 安裝]
    C --> D[Argo CD GitOps]
    D --> E[Helm 應用部署]
```

### 階段詳解

1. **前置作業** - SSH 金鑰、網路配置、Ubuntu 模板準備
2. **Terraform** → 建立 4 個 VM 節點並配置網路
3. **Ansible** → 安裝 Kubernetes、Calico CNI、初始化控制平面
4. **Argo CD** → 啟動 GitOps 控制面
5. **Helm** → 部署所有基礎設施與應用服務

> [!TIP]
> 所有應用服務集中部署在單一 app-worker 節點，便於展示和維護


## 最佳化建議檢查清單 (持續更新中)
- [ ] Root Application 與 ApplicationSet 為 `Synced`/`Healthy`
- [ ] Root Application 使用 `platform-bootstrap` AppProject，避免讓具有廣泛權限的 default AppProject 對 bootstrap 與業務應用的存取控制。
  - `argocd/root-argocd-app.yaml` 的 `spec.project` 必須設為 `platform-bootstrap`。
- [ ] 使用 ApplicationSet 區分環境 overlay。  
- [ ] 命名空間具備 `app.kubernetes.io/managed-by=gitops` 與推薦標籤
- [ ] 所有 `targetRevision` 皆固定為 `main`，禁止使用 `HEAD` 造成不可預期的 commit 漂移。
- [ ] Secret 類資源均透過外掛 ESO 同步代理 Vault 中授權的機密到 Pod 可使用的 Kubernetes Secret，無明文憑證。

## 集群架構與資源配置

### 節點配置總覽

| 節點 | Hostname | IP | Role | CPU | 記憶體 | 磁碟 | 主要工作負載 |
|------|----------|----|------|-----|--------|------|--------------|
| **VM-1** | master-1 | 192.168.0.11 | Control Plane | 4 cores | 8 GB | 100 GB | API Server + ETCD + Prometheus |
| **VM-2** | master-2 | 192.168.0.12 | Control Plane | 3 cores | 8 GB | 100 GB | API Server + ETCD + Mimir |
| **VM-3** | master-3 | 192.168.0.13 | Control Plane | 3 cores | 8 GB | 100 GB | API Server + ETCD + Loki |
| **VM-4** | app-worker | 192.168.0.14 | Application | 12 cores | 24 GB | 100GB (sys) + 250GB (data) | Argo CD, Keycloak, Grafana, Tempo, PostgreSQL, Vault |

### 設計說明

- **Control Plane**: 3 節點 HA 架構，分散監控元件 (Prometheus/Mimir/Loki)
- **Application Node**: 單一節點集中部署所有應用服務，便於展示和維護
- **Storage**:
  - Master 節點: 100GB (OS + etcd)
  - Worker 節點: 雙磁碟架構
    - 系統磁碟 (`/dev/sda`): 100GB (OS + kubelet)
    - 資料磁碟 (`/dev/sdb`): 250GB (TopoLVM `data-vg`，供應用動態 PV)
- **總資源**: 22 CPU cores, 48 GB RAM, 650 GB 儲存空間

### 節點標籤與調度策略

| 節點類型 | Kubernetes 標籤 | 容忍度 (Tolerations) | Pod 調度策略 |
|---------|----------------|-------------------|-------------|
| **Control Plane** | `node-role.kubernetes.io/control-plane` | - | 系統元件 (API Server, ETCD, Scheduler, Controller Manager) |
| **Worker** | `node-role.kubernetes.io/workload-apps: "true"` | - | 所有應用工作負載 (Ingress, Prometheus, Grafana, Loki 等) |

**調度規則**：
- 基礎設施元件 (MetalLB, cert-manager, ingress-nginx) 使用 `nodeSelector: workload-apps` 部署到 worker
- 觀測性元件 (Prometheus, Mimir, Loki) 統一使用 `nodeSelector: workload-apps` 部署到 worker
- 應用服務 (ArgoCD, Grafana, Vault, Keycloak) 部署到 worker
- Control Plane 元件保留給 Kubernetes 系統服務使用

## 網域規劃

### 公網域名 (detectviz.com)
本網域配置設計目的是展示平台整合能力，並將各功能區分子網域以供公開訪問。

1. **註冊**: GoDaddy 註冊網域 detectviz.com
2. **DNS Provider**: Cloudflare 管理，NS 伺服器指向 Cloudflare
3. **子網域配置**:
   - `blog.detectviz.com` → GitHub Pages (技術部落格)
   - `grafana.detectviz.com` → 公網展示儀表板
   - `argocd.detectviz.com` → GitOps 管理介面

### 內部域名 (detectviz.internal)
內部網路使用 `.internal` 頂級域名，由 Proxmox dnsmasq 提供 DNS 解析。

- **detectviz.internal**: 外部網路域名 (192.168.0.x)
  - `proxmox.detectviz.internal` → 192.168.0.2
  - `ipmi.detectviz.internal` → 192.168.0.4
  - `k8s-api.detectviz.internal` → 192.168.0.10 (VIP)
  - `argocd.detectviz.internal` → 192.168.0.10 (Ingress)
  - `grafana.detectviz.internal` → 192.168.0.10 (Ingress)
  - `master-{1,2,3}.detectviz.internal` → 192.168.0.{11,12,13}
  - `app-worker.detectviz.internal` → 192.168.0.14

- **cluster.internal**: 內部集群網路域名 (10.0.0.x)
  - `master-{1,2,3}.cluster.internal` → 10.0.0.{11,12,13}
  - `app-worker.cluster.internal` → 10.0.0.14

### Network Configuration

#### 雙網路架構設計
- **外部網路 (vmbr0)**: 192.168.0.0/24 - 管理界面與應用訪問
- **內部集群網路 (vmbr1)**: 10.0.0.0/24 - Kubernetes 節點間通訊

#### 節點 IP 分配
| 節點 | 外部 IP (vmbr0) | 內部 IP (vmbr1) | 用途 |
|------|----------------|----------------|------|
| Proxmox | 192.168.0.2 | - | 虛擬化管理平台 + DNS |
| IPMI | 192.168.0.4 | - | 硬體管理介面 |
| **VIP** | **192.168.0.10** | - | Kubernetes API + Ingress |
| master-1 | 192.168.0.11 | 10.0.0.11 | Control Plane + Prometheus |
| master-2 | 192.168.0.12 | 10.0.0.12 | Control Plane + Mimir |
| master-3 | 192.168.0.13 | 10.0.0.13 | Control Plane + Loki |
| app-worker | 192.168.0.14 | 10.0.0.14 | 應用工作負載 |

#### 域名規劃
- **detectviz.internal**: 外部域名 (應用訪問，解析至 192.168.0.x)
  - `argocd.detectviz.internal` → 192.168.0.10
  - `grafana.detectviz.internal` → 192.168.0.10
  - `prometheus.detectviz.internal` → 192.168.0.10
- **cluster.internal**: 內部域名 (節點通訊，解析至 10.0.0.x)
  - `master-{1,2,3}.cluster.internal` → 10.0.0.{11,12,13}

#### Kubernetes 網路
- **Pod CIDR**: 10.244.0.0/16 (Calico IPAM)
- **Service CIDR**: 10.96.0.0/12
- **CNI**: Calico with NetworkPolicy enforcement
- **CNI MTU**: 8950 (Jumbo Frames - 50 bytes VXLAN overhead)

#### LoadBalancer 配置
- **MetalLB Mode**: L2 (Layer 2 mode)
- **IP Pool**: 192.168.0.200-220
- **預留 VIP**: 192.168.0.10 (由 Kube-VIP 管理)

#### DNS 配置
- **主 DNS**: 192.168.0.2 (Proxmox dnsmasq)
- **備用 DNS**: 8.8.8.8
- **搜尋域**: detectviz.internal, cluster.internal

#### 網路優化
- **MTU**: 9000 (Jumbo Frames)
- **rp_filter**: 2 (Loose mode，支援雙網路非對稱路由)
- **ip_forward**: 1 (啟用 IP 轉發)
- **Bridge netfilter**: enabled (支援 NetworkPolicy)

### Service Ports
| Service | Port | Protocol | Purpose |
| --- | --- | --- | --- |
| K8s API | 6443 | TCP | Kubernetes API |
| ETCD | 2379-2380 | TCP | Cluster state |
| Grafana | 3000 | HTTP | Web UI |
| Prometheus | 9090 | HTTP | Metrics |
| Alertmanager | 9093 | HTTP | Alerts |
| Ingress | 80/443 | HTTP/HTTPS | External access |

> [!NOTE]
> 本配置為單叢集設計，可擴展至多叢集環境，並支援 staging/production overlay。

## 硬體規格

- **處理器**: Intel(R) Core(TM) i7-14700F, 20 Core(s), 28 Logical Processors(s)
- **記憶體**: D5-6000-32GB × 2 (64 GB total)
- **儲存**: TEAM TM8FPW002T 2048GB (NVMe) + Acer SSD RE100 2.5 512GB (SATA)
- **網路**: Intel I210-AT (支援 1Gbps)

### VM 資源分配

- **VM ID 範圍**: 111~114 (master-1 ~ app-worker)
- **域名**:
  - 外部: `*.detectviz.internal` (管理和應用訪問)
  - 內部: `*.cluster.internal` (Kubernetes 節點通訊)
- **網路橋接器**:
  - vmbr0 (外部網路，192.168.0.0/24，MTU 9000)
  - vmbr1 (內部集群網路，10.0.0.0/24，MTU 9000)
- **網路介面**: 每個 VM 配置 2 個 VirtIO 網卡 (eth0 + eth1)