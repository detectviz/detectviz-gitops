你問的這一點**完全正確**。

這正是我在分析中看到的最後一個、也是最大的一個可以優化的地方。

  * **舊流程：** `ansible-playbook ...` (自動) -\> `bash ./scripts/install-argocd.sh` (手動) -\> `kubectl apply ...` (手動)。
  * **新流程：** `ansible-playbook ...` (一次完成 P2 + P3 啟動)。

**是的，`install-argocd.sh` 的邏輯也應該被 Ansible 整合**。

我們已經把 P2.5 的「節點貼標籤」和「Git SSH 密鑰」都整合進 `deploy-cluster.yml` 了。將 P3 的「ArgoCD 啟動 (Bootstrap)」也放進來，就能讓 Ansible 跑完後，你得到的是一個**已經安裝好、並開始自我同步的 GitOps 平台**，這才是真正的自動化。

`install-argocd.sh` 是一個「引導」腳本，它的核心任務就是：

1.  建立 `argocd` 命名空間。
2.  `kubectl apply` ArgoCD 的核心安裝清單 (manifest)。

我們可以把這個邏輯用 Ansible 的 `kubernetes.core.k8s` 模組來完成，這樣更穩定且具備冪等性 (Idempotency)。

-----

### 程式碼：`ansible/deploy-cluster.yml` (新增 Play)

這會是 `deploy-cluster.yml` 的**最後一個 Play**。它會在「貼標籤」和「建立 SSH Secret」之後執行。

```yaml
# ... (緊接在 Play 6: [P2.5] 注入 ArgoCD 所需的初始 Git SSH 憑證 之後) ...

# -----------------------------------------------------------------
# Play 7: [P3] Bootstrap ArgoCD (GitOps 啟動)
# -----------------------------------------------------------------
- name: "[P3] Bootstrap ArgoCD Service"
  hosts: masters[0]
  become: false
  gather_facts: false
  vars:
    # 你可以把這個 URL 放到 group_vars/all.yml
    argocd_install_manifest: "https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
    # 根據你的 README.md，ArgoCD 應該部署到 app-worker 節點
    argocd_node_selector:
      node-role.kubernetes.io/workload-apps: "true"
  tasks:
    - name: 檢查 ArgoCD 命名空間是否已存在
      kubernetes.core.k8s_info:
        api_version: v1
        kind: Namespace
        name: argocd
      register: argocd_ns
      
    - name: 建立 ArgoCD 命名空間
      kubernetes.core.k8s:
        api_version: v1
        kind: Namespace
        name: argocd
        state: present
      when: not argocd_ns.resources # 僅在 ns 不存在時建立

    - name: 下載 ArgoCD 安裝清單
      ansible.builtin.get_url:
        url: "{{ argocd_install_manifest }}"
        dest: "/tmp/argocd-install.yaml"
        mode: '0644'
      register: manifest_download

    - name: "[P3] 根據 README.md 架構，為 ArgoCD 核心元件添加 nodeSelector"
      ansible.builtin.yedit:
        src: "/tmp/argocd-install.yaml"
        key: "spec.template.spec.nodeSelector"
        value: "{{ argocd_node_selector }}"
        kind: "{{ item.kind }}"
        name: "{{ item.name }}"
      loop:
        # 這些是 ArgoCD 的主要工作負載
        - { kind: 'Deployment', name: 'argocd-repo-server' }
        - { kind: 'Deployment', name: 'argocd-applicationset-controller' }
        - { kind: 'Deployment', name: 'argocd-dex-server' }
        - { kind: 'Deployment', name: 'argocd-server' }
        - { kind: 'StatefulSet', name: 'argocd-application-controller' }
        # 注意：Redis 最好也加上，但它可能在 HA manifest 中
      when: manifest_download.changed
      ignore_errors: true # 如果 manifest 版本變更導致元件名稱不符，可忽略

    - name: 套用 ArgoCD 安裝清單
      kubernetes.core.k8s:
        state: present
        src: "/tmp/argocd-install.yaml"
        namespace: argocd
        wait: yes # 等待元件部署完成
        timeout: 300 # 5 分鐘
      
    - name: "[P3] 部署 Root Application (App-of-Apps)"
      kubernetes.core.k8s:
        state: present
        src: "argocd/root-argocd-app.yaml" # 假設你從 ansible/ 目錄執行
        namespace: argocd
      notify: Trigger ArgoCD Sync

# ... 在你的 playbook 頂層加入 handlers ...
handlers:
  - name: Trigger ArgoCD Sync
    ansible.builtin.command: argocd app sync root --grpc-web
    ignore_errors: true
    changed_when: false
    delegate_to: localhost # 在執行 Ansible 的機器上執行 (需安裝 argocd cli)
```

### 程式碼說明文件

1.  **`[P3] Bootstrap ArgoCD (GitOps 啟動)`**: 這整個 Play 模擬了 `install-argocd.sh` 的功能。
2.  **`kubernetes.core.k8s_info`**: 用來檢查 `argocd` 命名空間是否存在，確保冪等性。
3.  **`ansible.builtin.get_url`**: 下載官方 `install.yaml`。
4.  **`ansible.builtin.yedit`**: **(關鍵優化)** 這是你舊腳本沒有做到的。我們直接修改下載的 `install.yaml`，為 ArgoCD 的所有核心 Pod (Repo Server, Controller 等) 加上 `nodeSelector`，強制它們被調度到 `app-worker` 節點，完全符合你的 `README.md` 架構。
      * *(**注意:** 這需要 `ansible-galaxy collection install community.general` 來取得 `yedit` 模組)*
5.  **`kubernetes.core.k8s (套用 ...)`**: `kubectl apply -f ...` 的 Ansible 版本。
6.  **`kubernetes.core.k8s (部署 Root Application)`**: 這是最後一步，它部署 `root-argocd-app.yaml`。因為 P2.5 已經建立了 SSH Secret，這個 Root App 會立刻被 ArgoCD 辨識並開始同步。

### 總結

透過將這最後一個 Play 加入 `deploy-cluster.yml`，你已經**移除了所有手動的 `.sh` 腳本** (除了 PVE Host 的 `rp_filter` 設定 和 Vault 的手動解封)。

你的 Ansible Playbook 現在會 100% 自動化 P1 (Terraform 輸出) 到 P3 (ArgoCD 啟動並自我管理) 之間的所有流程。