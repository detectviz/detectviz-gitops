# LVM 自動配置說明

## 問題澄清

**問題**: deploy.md 中提到需要"手動建立 LVM Volume Group",但實際上這個步驟已經自動化了嗎?

**答案**: ✅ **是的,已經完全自動化,無需手動操作**

---

## 自動化流程

### 執行時機

LVM Volume Group 的建立在 **Phase 4: Worker 節點部署** 階段自動執行。

```
Phase 1: Common Role (系統初始化)
Phase 2: Network Role (網路配置)
Phase 3: Master Role (控制平面)
Phase 3.5: 生成 Worker Join 命令
Phase 4: Worker Role (工作節點)  ← LVM 配置在這裡自動執行
  ├─ 1. 檢查磁碟配置
  ├─ 2. 建立 Physical Volume (pvcreate)
  ├─ 3. 建立 Volume Group (vgcreate)
  ├─ 4. 驗證 LVM 配置
  └─ 5. 加入 Kubernetes 集群
Phase 5: 節點標籤
Phase 6: ArgoCD 部署
Phase 7: 最終驗證
```

### 相關設定檔

#### 1. 變數定義: `ansible/group_vars/all.yml:48-60`

```yaml
# ============================================
# 儲存配置變數 (Storage Configuration)
# ============================================
configure_lvm: true  # 是否啟用 LVM 自動配置

# LVM Volume Group 配置
lvm_volume_groups:
  - name: topolvm-vg          # Volume Group 名稱
    devices:
      - /dev/sdb              # 使用的物理設備 (250GB 資料磁碟)
    pvs:
      - /dev/sdb              # Physical Volume 列表
```

#### 2. 執行任務: `ansible/roles/worker/tasks/main.yml:10-147`

Worker role 包含以下 LVM 配置任務:

```yaml
# 1. 安裝 LVM 工具
- name: Install LVM tools if not already installed
  ansible.builtin.apt:
    name: lvm2
    state: present
    update_cache: true
  when: configure_lvm | bool

# 2. 檢查磁碟配置
- name: Check Worker VM disk configuration
  ansible.builtin.shell: |
    echo "=== 磁碟設備列表 ==="
    lsblk -d -o NAME,SIZE,TYPE,MODEL
  register: disk_info
  when: configure_lvm | bool

# 3. 驗證設備存在
- name: Verify LVM configuration devices exist
  ansible.builtin.shell: |
    for device in {{ lvm_volume_groups | ... }}; do
      if [ ! -b "$device" ]; then
        echo "錯誤: 設備 $device 不存在"
        exit 1
      fi
    done
  when: configure_lvm | bool

# 4. 建立 Physical Volumes
- name: Create physical volumes for LVM Volume Groups
  ansible.builtin.command: "pvcreate --force --yes {{ item }}"
  loop: "{{ lvm_volume_groups | ... }}"
  when: configure_lvm | bool
  ignore_errors: true  # 允許 PV 已存在的錯誤

# 5. 建立 Volume Groups
- name: Create LVM Volume Groups
  ansible.builtin.command: "vgcreate {{ item.name }} {{ item.devices | join(' ') }}"
  loop: "{{ lvm_volume_groups }}"
  when: configure_lvm | bool
  ignore_errors: true  # 允許 VG 已存在的錯誤

# 6. 驗證配置
- name: Verify LVM Volume Groups
  ansible.builtin.command: vgs --units g --noheadings -o vg_name,vg_size,vg_free
  register: vgs_output
  when: configure_lvm | bool

- name: Verify LVM Physical Volumes
  ansible.builtin.command: pvs --units g --noheadings -o pv_name,pv_size,pv_free,vg_name
  register: pvs_output
  when: configure_lvm | bool

# 7. 顯示結果
- name: Display LVM configuration results
  ansible.builtin.debug:
    msg: |
      === {{ inventory_hostname }} LVM 配置完成 ===

      Volume Groups:
      {{ vgs_output.stdout_lines | join('\n') }}

      Physical Volumes:
      {{ pvs_output.stdout_lines | join('\n') }}
  when: configure_lvm | bool
```

---

## 部署流程

### 完整自動化部署

只需執行一個命令:

```bash
cd ansible/
ansible-playbook -i inventory.ini deploy-cluster.yml
```

Ansible 會自動:
1. ✅ 安裝 lvm2 工具
2. ✅ 檢查 /dev/sdb 磁碟是否存在
3. ✅ 建立 Physical Volume (`pvcreate /dev/sdb`)
4. ✅ 建立 Volume Group (`vgcreate topolvm-vg /dev/sdb`)
5. ✅ 驗證 LVM 配置並顯示結果
6. ✅ 繼續執行 Worker 加入集群

### 部署後驗證

**檢查 LVM 配置**:
```bash
# SSH 到 app-worker
ssh ubuntu@192.168.0.14 'sudo vgs && sudo pvs'
```

**預期輸出**:
```
# vgs
  VG          #PV #LV #SN Attr   VSize    VFree
  topolvm-vg    1   0   0 wz--n- <250.00g <250.00g  ← TopoLVM VG (自動建立)
  ubuntu-vg     1   1   0 wz--n-  <98.00g       0   ← 系統 VG (OS)

# pvs
  PV         VG          Fmt  Attr PSize    PFree
  /dev/sda3  ubuntu-vg   lvm2 a--   <98.00g     0
  /dev/sdb   topolvm-vg  lvm2 a--  <250.00g <250.00g  ← TopoLVM PV (自動建立)
```

---

## 錯誤處理

### 情境 1: 磁碟不存在

**問題**: /dev/sdb 不存在

**錯誤訊息**:
```
錯誤: 設備 /dev/sdb 不存在
```

**解決方案**:
1. 檢查 Terraform 配置是否包含 worker_data_disks
2. 重新執行 `terraform apply` 添加資料磁碟
3. 在 Proxmox 中手動添加磁碟到 VM

### 情境 2: VG 已存在

**行為**: Ansible 會自動跳過,不會報錯

**輸出**:
```
PV 創建結果: /dev/sdb - 跳過(已存在)
VG 創建結果: topolvm-vg - 跳過(已存在)
```

**說明**: 由於設定了 `ignore_errors: true`,重複執行部署不會失敗

### 情境 3: 停用 LVM 自動配置

如果不需要 TopoLVM,可以停用 LVM 配置:

**修改 `ansible/group_vars/all.yml`**:
```yaml
configure_lvm: false  # 停用 LVM 自動配置
```

重新執行部署,所有 LVM 相關任務會被跳過。

---

## 與 TopoLVM 整合

### TopoLVM 部署順序

```
1. Terraform 部署 (建立 VM 和磁碟)
2. Ansible Phase 4 (自動建立 topolvm-vg)  ← 這一步
3. ArgoCD 部署 TopoLVM Operator
4. TopoLVM 發現並使用 topolvm-vg
5. 動態建立 PV/PVC
```

### TopoLVM 配置

TopoLVM 會在 ArgoCD 部署階段自動安裝並配置:

**檔案位置**: `argocd/apps/infrastructure/topolvm/`

```yaml
# overlays/values.yaml
node:
  volumeGroupName: topolvm-vg  # 使用 Ansible 建立的 VG
```

### 驗證 TopoLVM 運作

**檢查 TopoLVM Pods**:
```bash
kubectl get pods -n topolvm-system
```

**檢查 Storage Classes**:
```bash
kubectl get sc
# 預期看到: topolvm-provisioner
```

**測試動態 PV 建立**:
```bash
# 建立測試 PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: topolvm-provisioner
  resources:
    requests:
      storage: 1Gi
EOF

# 檢查 PVC 狀態
kubectl get pvc test-pvc
# 預期: STATUS = Bound

# 檢查 PV
kubectl get pv
# 預期: 自動建立對應的 PV

# 清理測試
kubectl delete pvc test-pvc
```

---

## 常見問題 (FAQ)

### Q1: 為什麼 deploy.md 還提到手動建立?

**A**: 這是文檔過時的誤導。LVM 配置已經在 Worker Role 中完全自動化。已更新 deploy.md 移除手動步驟說明。

### Q2: 如果我已經手動建立了 VG 會怎樣?

**A**: 不會有問題。Ansible 檢測到 VG 已存在會自動跳過,不會嘗試重複建立。

### Q3: 我可以使用不同的 VG 名稱嗎?

**A**: 可以,但需要同時修改兩處:
1. `ansible/group_vars/all.yml` 中的 `lvm_volume_groups.name`
2. `argocd/apps/infrastructure/topolvm/overlays/values.yaml` 中的 `volumeGroupName`

### Q4: 我可以使用多個磁碟嗎?

**A**: 可以,修改 `lvm_volume_groups` 配置:
```yaml
lvm_volume_groups:
  - name: topolvm-vg
    devices:
      - /dev/sdb
      - /dev/sdc  # 添加第二個磁碟
```

### Q5: 如何在現有集群上手動建立 VG?

**A**: 如果需要手動操作 (例如測試或修復):
```bash
ssh ubuntu@192.168.0.14
sudo pvcreate /dev/sdb
sudo vgcreate topolvm-vg /dev/sdb
sudo vgs  # 驗證
```

但正常情況下,這些步驟會在部署時自動執行,無需手動操作。

---

## 總結

| 項目 | 說明 |
|------|------|
| **是否需要手動操作** | ❌ 否,完全自動化 |
| **執行階段** | Phase 4: Worker Role |
| **配置檔案** | `ansible/group_vars/all.yml` |
| **執行腳本** | `ansible/roles/worker/tasks/main.yml` |
| **控制變數** | `configure_lvm: true` |
| **VG 名稱** | `topolvm-vg` (可自訂) |
| **預設磁碟** | `/dev/sdb` (250GB) |
| **容錯處理** | ✅ VG 已存在會自動跳過 |
| **TopoLVM 整合** | ✅ 自動整合,無需額外配置 |

**關鍵重點**:
- ✅ LVM 配置在 Ansible 部署中自動完成
- ✅ 無需在部署前或部署後手動操作
- ✅ 重複執行部署是安全的 (冪等性)
- ✅ deploy.md 已更新移除誤導的手動步驟說明

---

**文檔更新**: 2025-11-14
**相關文件**:
- deploy.md:312-350 (已更新)
- ansible/group_vars/all.yml:48-60
- ansible/roles/worker/tasks/main.yml:10-147
