# 儲存架構與設定指南

本文件說明 Detectviz 混合儲存（Hybrid Storage）配置方式，包含 NVMe 與 SATA 的分層設計。

## 目錄

- [硬體與邏輯架構](#1-硬體與邏輯架構)
- [Proxmox 儲存設置步驟](#2-proxmox-儲存設置步驟)
  - [儲存磁碟規格](#21-儲存磁碟規格)
  - [儲存分配策略](#22-儲存分配策略)
  - [儲存架構規劃](#23-儲存架構規劃)
  - [NVMe 初始化與設定高效儲存池](#24-nvme-初始化與設定高效儲存池)
  - [設定 SATA 備份區](#25-設定-sata-備份區同一顆硬碟內的子目錄)
  - [檢查儲存池結構](#26-檢查儲存池結構)
  - [驗證說明](#27-驗證說明)
- [TopoLVM 設定](#3-topolvm-設定)
  - [Worker VM 磁碟配置](#31-worker-vm-磁碟配置)
  - [VM 內部 LVM 設定](#32-vm-內部-lvm-設定)
  - [TopoLVM 安裝](#33-topolvm-安裝)
  - [TopoLVM 配置](#34-topolvm-配置)
- [Kubernetes 驗證步驟](#4-kubernetes-驗證步驟)
  - [TopoLVM 狀態檢查](#41-topolvm-狀態檢查)
  - [StorageClass 檢查](#42-storageclass-檢查)
  - [PVC 測試](#43-pvc-測試)
- [設計原則](#5-設計原則)
- [相關文檔](#相關文檔)

---

## 1. 硬體與邏輯架構

| 層級 | 裝置 | Volume Group | 掛載點 / Pool | 用途 |
|------|------|---------------|----------------|------|
| **系統層** | SATA SSD `/dev/sda` | pve | `/`, `/var/lib/vz`, `/mnt/sata-backup` | Proxmox 系統與備份 |
| **高效層** | NVMe SSD `/dev/nvme0n1` | nvme-vg | `nvme-vm` | VM、容器、高 I/O 工作負載 |
| **邏輯備份層** | `/mnt/sata-backup` (bind mount) | pve-root | `detectviz-sata` | 備份、Mimir、Loki 長期儲存 |

---

## 2. Proxmox 儲存設置步驟

### 2.1 儲存磁碟規格
- Acer RE100 512GB SATA SSD（讀 562 MB/s、寫 529 MB/s）
- TEAM MP44 2TB NVMe Gen4 SSD（讀 7400 MB/s、寫 7000 MB/s）

### 2.2 儲存分配策略
- 將 SATA (Acer RE100) 作為主存放區：Proxmox 作業系統與核心服務，並於同一顆硬碟內設置備份資料區 `/mnt/sata-backup`（存放 ISO、模板、VM 備份）。
- 將 NVMe (TEAM MP44) 建立高效儲存區：`nvme-vm`，用於 VM 系統碟、容器、高效能工作負載。

### 2.3 儲存架構規劃

#### ZFS 與 LVM-Thin 比較

- **ZFS**：
  - 適用於需要高度資料完整性保護、快照與複製功能的環境。
  - 支援內建 RAID、壓縮與自動修復，適合資料庫與重要資料存放。
  - 需要較多記憶體資源，且配置較複雜。
- **LVM-Thin**：
  - 適合追求高效能與簡單管理的虛擬化環境。
  - 支援快速快照與節省空間的薄配置。
  - 管理較為簡單，適合一般 VM 與容器使用。

根據需求選擇，若重視資料安全與完整性，建議使用 ZFS；若偏重效能與簡易管理，LVM-Thin 是較佳選擇。

#### 各層級說明

- **系統層**
  - **儲存設備**：SATA 512 GB
  - **掛載點**：`/`
  - **用途**：Proxmox 作業系統與核心服務

- **高效儲存層**
  - **儲存設備**：NVMe 2 TB
  - **掛載點**：`/dev/pve/nvme-vm` (由 Proxmox 自動管理)
  - **用途**：VM 系統碟、容器、AI 模型、資料庫

- **備份層（Proxmox 主機層級）**
  - **儲存設備**：同一顆 SATA 分割或子目錄（512 GB）
  - **掛載點**：`/mnt/sata-backup`（僅在 Proxmox 主機可見）
  - **用途**：VM 備份、ISO 映像檔、LXC 模板、Proxmox 快照
  - **說明**：此儲存不會掛載到 VM 內部，僅供 Proxmox 管理平台使用

### 2.4 NVMe 初始化與設定高效儲存池

#### 建立物理卷與卷組
```bash
pvcreate /dev/nvme0n1
vgcreate nvme-vg /dev/nvme0n1
```

#### 建立 LVM-Thin Pool
```bash
lvcreate -l 100%FREE -T nvme-vg/nvme-vm
```

#### 在 Proxmox 註冊儲存池
```bash
pvesh create /storage \
  -storage nvme-vm \
  -type lvmthin \
  -vgname nvme-vg \
  -thinpool nvme-vm \
  -content images,rootdir
```

> 成功結果會顯示：
```bash
┌─────────┬─────────┐
│ key     │ value   │
╞═════════╪═════════╡
│ storage │ nvme-vm │
├─────────┼─────────┤
│ type    │ lvmthin │
└─────────┴─────────┘
```

### 2.5 設定 SATA 備份區（同一顆硬碟內的子目錄）

由於 SATA SSD 空間已由 LVM 管理，無法再切出新的分割區，
建議直接使用 Proxmox 預設資料目錄 `/var/lib/vz` 來建立備份區。

1. **建立掛載點並設定 bind 掛載**：
```bash
mkdir -p /mnt/sata-backup
echo '/var/lib/vz /mnt/sata-backup none bind 0 0' >> /etc/fstab
mount -a
systemctl daemon-reload
```

2. **新增至 Proxmox 儲存池**：
```bash
pvesh create /storage \
  -storage sata-backup -type dir -content backup,iso,vztmpl \
  -path /mnt/sata-backup
```

> `/var/lib/vz` 已位於 `pve-data` LVM-Thin Pool 內，綁定掛載可直接使用同一顆 SATA 硬碟空間，
> 提供備份、ISO、模板與快照功能而不需重新分割磁碟。

### 2.6 檢查儲存池結構

```bash
pvesm status
```

範例輸出：
```bash
Name               Type     Status           Total            Used       Available        %
local               dir     active       100597760         3630676        96967084    3.61%
local-lvm       lvmthin     active       365760512               0       365760512    0.00%
nvme-vm         lvmthin     active      2000150528               0      2000150528    0.00%
sata-backup         dir     active       100597760         3630676        96967084    3.61%
```

### 2.7 驗證說明

> 四個儲存池均顯示 `active` 即代表設定完成且運作正常。

安裝完成後：
```bash
pveversion
pvesm status
df -h
```

---

## 3. TopoLVM 設定

**重要**: 由於Worker節點運行在VM中，無法直接訪問Proxmox主機的LVM子系統。需要在每個Worker VM內部建立獨立的LVM。

### 3.1 Worker VM 磁碟配置

1. **Proxmox VM 設定**: 給每個Worker VM添加額外的raw disk
   - 格式: raw (非qcow2)
   - 大小: 200-400GB (根據需求)
   - Bus: SCSI 或 VirtIO Block
   - **重要**: 不要被Proxmox LVM池管理

2. **VM 內部磁碟識別**:
   ```bash
   # 在VM內部檢查
   lsblk
   # 應該看到 /dev/sdb (額外的資料磁碟)
   ```

### 3.2 VM 內部 LVM 設定

#### 手動配置 (每個VM單獨執行)

```bash
# 在每個 Worker VM 內部執行
sudo apt-get update && sudo apt-get install -y lvm2

# 建立 LVM
sudo pvcreate /dev/sdb
sudo vgcreate data-vg /dev/sdb
sudo vgs  # 確認 data-vg 已建立
```

#### Ansible 自動化配置 (推薦)

編輯 `ansible/group_vars/all.yml`:

```yaml
# LVM 儲存配置 (僅適用於 Worker 節點)
configure_lvm: true
lvm_volume_groups:
  - name: "data-vg"
    devices: ["/dev/sdb"]
```

執行自動化配置:

```bash
# 執行 worker role 配置 LVM
ansible-playbook -i ansible/inventory.ini ansible/deploy-cluster.yml --tags worker

# 驗證配置
ansible workers -i ansible/inventory.ini -m shell -a "sudo vgs" -b
```

### 3.3 TopoLVM 安裝

```bash
# 安裝 cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.15.0/cert-manager.yaml

# 安裝 TopoLVM
helm repo add topolvm https://topolvm.github.io/topolvm
helm repo update

helm install topolvm topolvm/topolvm \
  --namespace kube-system \
  --create-namespace \
  --set controller.replicas=1 \
  --set lvmd.managed=true \
  --set 'lvmd.deviceClasses[0].name=data' \
  --set 'lvmd.deviceClasses[0].volume-group=data-vg' \
  --set 'lvmd.deviceClasses[0].default=false' \
  --set 'lvmd.deviceClasses[0].spare-gb=20'
```

### 3.4 TopoLVM 配置

**設定檔：`/etc/topolvm/lvmd.yaml`**
```yaml
socket-name: /run/topolvm/lvmd.sock
device-classes:
  - default: false
    name: data
    spare-gb: 20
    volume-group: data-vg
```

---

## 4. Kubernetes 驗證步驟

### 4.1 TopoLVM 狀態檢查
```bash
# 檢查 TopoLVM 組件
kubectl -n kube-system get pods -l app.kubernetes.io/name=topolvm

# 檢查 lvmd
kubectl -n kube-system get pods -l app.kubernetes.io/component=lvmd

# 檢查 logical volumes（測試後）
kubectl get logicalvolumes.topolvm.io -A
```

### 4.2 StorageClass 檢查
```bash
kubectl get storageclass
```

### 4.3 PVC 測試
```bash
# 測試 PVC
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: detectviz-data
  resources:
    requests:
      storage: 5Gi
EOF

kubectl get pvc test-pvc
```

---

## 5. 設計原則

- **分層隔離**：
  - **Proxmox 層**：SATA (系統 + 備份) 與 NVMe (VM 儲存池) 由 Proxmox 管理
  - **VM 層**：每個 Worker VM 建立獨立的 LVM，由 TopoLVM 動態管理

- **VM 內部 LVM**：每個 Worker VM 建立獨立的 LVM，避免虛擬化層阻斷問題

- **TopoLVM 動態管理**：在 VM 內部提供動態容量分配和 thin provisioning

- **Proxmox 備份層**：SATA 備份區僅供 Proxmox 使用（ISO、模板、VM 備份），不掛載到 VM

- **可擴充性**：未來可新增更多 VM 磁碟或 NFS/Ceph 儲存類別


## 相關文檔

- [儲存架構設計](storage-architecture.md)
- [Proxmox 配置指南](../proxmox/configuration.md)
- [硬體規格說明](../hardware/hardware-specs.md)
