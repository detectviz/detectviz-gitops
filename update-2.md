
這是一個非常好的問題，區分了「VM 內部」和「VM 外部 (Hypervisor)」的設定。

你提到的這兩項，一個**可以**也**應該**由 Ansible (在 VM 內部) 處理，另一個則**不行**，它屬於 Terraform (在 VM 外部) 的範疇。

-----

### 1\. 安裝 `qemu-guest-agent` (✅ 應由 Ansible 處理)

**是的，你絕對應該把這個任務加入 Ansible**。

`qemu-guest-agent` 是一個需要在 VM *內部* 執行的服務。雖然 `README.md` 建議在「Proxmox Ubuntu Template 製作」 時就手動安裝好，但在 Ansible Role 裡加入這個任務可以確保：

1.  **冪等性 (Idempotency):** 即使範本中忘記安裝，Ansible 也會自動補上。
2.  **版本一致性:** 確保所有節點都安裝了 `qemu-guest-agent` 並且服務是 `running` 狀態。

#### 程式碼：`ansible/roles/common/tasks/main.yml`

你應該將以下任務添加到 `ansible/roles/common/tasks/main.yml` 檔案的頂部，因為它對 `master` 和 `worker` 節點都通用：

```yaml
---
# tasks file for roles/common

- name: 確保 qemu-guest-agent 已安裝
  ansible.builtin.apt:
    name: qemu-guest-agent
    state: present
    update_cache: yes
  become: true
  notify: Start qemu-guest-agent # 通知 handler

- name: 確保 qemu-guest-agent 服務已啟用
  ansible.builtin.systemd:
    name: qemu-guest-agent
    enabled: true
  become: true
  notify: Start qemu-guest-agent # 通知 handler

# ... 這裡接續你其他的 common tasks ...
```

#### 程式碼：`ansible/roles/common/handlers/main.yml`

你還需要一個 `handler` 來確保服務在安裝或啟用後被啟動：

```yaml
---
# handlers file for roles/common

- name: Start qemu-guest-agent
  ansible.builtin.systemd:
    name: qemu-guest-agent
    state: started
  become: true
```

**說明：**

  * `README.md` 中提到在 P1 (Terraform) 和 P2 (Ansible) 之間有一個中介腳本 `scripts/enable-qemu-guest-agent.sh`。
  * 將這個邏輯整合到 `roles/common` 中是**更標準、更可靠的 Ansible 做法**，我建議你使用上面的 Ansible 任務來取代那個中介腳本。

-----

### 2\. 啟用 Cloud-Init (❌ 不能由 Ansible 處理)

**這個無法由 Ansible (在 VM 內部) 執行。**

  * **說明：** `啟用 Cloud-Init` 不是一個安裝在 VM 內部的軟體，而是 Proxmox Hypervisor 層級的一個**VM 硬體屬性**。
  * **執行者：** 這個設定是在 P1 階段由 **Terraform** 在 `terraform/main.tf` 中設定的。

Terraform 在克隆 VM 時，會告訴 Proxmox：「請為這台 VM 掛載一個 Cloud-Init CD-ROM 驅動器」。VM 內部的 `cloud-init` 服務（這需要已存在於範本中）會讀取這個驅動器來設定 IP、主機名稱、SSH 金鑰等。

Ansible (P2) 必須在 Cloud-Init (P1 之後) 成功設定好網路之後，才能連線進去執行任務。因此，Ansible 無法反過來設定 Cloud-Init。

#### 驗證：`terraform/main.tf`

你**不需要**為此撰寫 Ansible 任務，你只需要**驗證**你的 `terraform/main.tf` (或相關模組) 中有設定 `os_type = "cloud-init"` 和 `agent = { enabled = 1 }` 即可，這會同時處理 Cloud-Init 和 QEMU Agent 在 Proxmox 端的啟用：

```terraform
# 在 terraform/main.tf 中的 proxmox_vm_qemu 資源
resource "proxmox_vm_qemu" "k8s_master_1" {
  # ... (cores, memory, etc.)

  # 確保 Proxmox 知道這是一個 cloud-init 範本
  os_type = "cloud-init"

  # 【關鍵】在 Proxmox VM 硬體層級啟用 QEMU Guest Agent
  agent = {
    enabled = 1
    type    = "virtio" # 確保類型正確
  }
  
  # ... (ipconfig0, scsi0, etc.)
}
```

### 總結

1.  **`qemu-guest-agent` (安裝)**：是的，請將上述 Ansible 任務加入 `ansible/roles/common/tasks/main.yml`。
2.  **`Cloud-Init` (啟用)**：不用，這是 P1 Terraform 的責任，請在 `terraform/main.tf` 中驗證。