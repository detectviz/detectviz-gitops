# DetectViz GitOps 部署手冊

**版本**: 1.0  
**最後更新**: 2025-11-08

> [!IMPORTANT]
> 任何由 GitOps 管理的資源請透過提交 Git 變更後讓 Argo CD 同步。除非另有註明的手動流程（例如 Vault 初始化、節點標籤同步腳本），請勿手動 `kubectl apply/delete`。

---

## 目錄
1. [部署前準備](#部署前準備)
2. [Phase 1: Terraform 基礎設施佈建](#phase-1-terraform-基礎設施佈建)
3. [Phase 2: Ansible 節點配置與 Kubernetes 初始化](#phase-2-ansible-節點配置與-kubernetes-初始化)
4. [Phase 3: GitOps Bootstrap（Argo CD 啟動）](#phase-3-gitops-bootstrapargo-cd-啟動)
5. [Phase 4: GitOps 管理的叢集服務驗證](#phase-4-gitops-管理的叢集服務驗證)
6. [Phase 5: 節點標籤同步（選擇性）](#phase-5-節點標籤同步選擇性)
7. [Phase 6: Vault + External Secrets Operator 整合](#phase-6-vault--external-secrets-operator-整合)
8. [最終驗證](#最終驗證)

---

## 部署前準備

| 工具 | 版本建議 | 用途 |
| --- | --- | --- |
| Terraform | ≥ 1.5 | Proxmox VM 宣告式佈建 |
| Ansible | ≥ 2.15 | VM 設定與 Kubernetes 初始化 |
| kubectl | 與 Kubernetes 相容 | 叢集驗證與疑難排解 |
| argocd CLI | ≥ 2.9 | GitOps 狀態檢視與操作 |
| vault CLI | ≥ 1.14 | Vault 初始化與設定 |

其他必要條件：
- 可存取 Proxmox API 的 Token（參考 `terraform/terraform.tfvars.example`）。
- 本地電腦具備到叢集各節點的 SSH 存取權。
- 若需透過域名訪問，請將 `/etc/hosts` 更新為 repo README 中列出的對應。

> [!CAUTION]
> 重新部署前務必確認 Terraform 狀態與叢集節點皆已清理乾淨。未清除的 kubeadm 狀態或舊 VM 可能導致 etcd 成員殘留與節點加入失敗。

---

## Phase 1: Terraform 基礎設施佈建

**目標**：在 Proxmox 上建立 Kubernetes 控制平面與工作節點虛擬機。

```bash
cd terraform

# 若為重新部署，可先執行清理腳本（會執行 terraform destroy 並釋放舊 VM）
./cleanup-and-redeploy.sh  # 約 15 分鐘
# 或手動執行下列命令：
# terraform destroy -auto-approve
# terraform init
# terraform apply -auto-approve

terraform output
```

驗證項目：
- `terraform output` 顯示所有節點 IP 與主機名稱。
- 可透過 `ssh ubuntu@<IP> "hostname -f"` 成功連線。
- 若 Terraform 指標與實際 VM 不一致，請檢查 `terraform state list` 並修正 `main.tf` 的 `count` 設定。

---

## Phase 2: Ansible 節點配置與 Kubernetes 初始化

**目標**：將所有節點初始化為高可用 Kubernetes 叢集。

```bash
cd ansible
ansible all -i inventory.ini -m ping

# 需要完整重置時可選擇執行
./scripts/cluster-cleanup.sh reset-cluster

# 佈署 Kubernetes 叢集（預設會檢查並清除舊的 kubeadm 狀態）
ansible-playbook -i inventory.ini deploy-cluster.yml -e reset_cluster=true -e force_rejoin=true

# 集群健康檢查
./scripts/validation-check.sh --phase2
./scripts/test-cluster-dns.sh
```

若遇到節點加入或 etcd 相關問題，可透過 `./scripts/cluster-cleanup.sh --help` 查詢對應的修復選項（例如 `check-etcd`、`network-cleanup`）。

---

## Phase 3: GitOps Bootstrap（Argo CD 啟動）

**目標**：安裝 Argo CD 並載入 `appsets/` 中的 App-of-Apps 架構，讓平台元件自動同步。

```bash
# 安裝 Argo CD（建立 argocd 命名空間並套用 base 資源）
bash scripts/install-argocd.sh

# 🔐 配置 GitHub App 認證（推薦）
# 1. 確保 GitHub App 已安裝到 detectviz 組織
# 2. 設置 repository secrets（已在 argocd-repositories.yaml 中配置）
kubectl apply -f apps/argocd/overlays/argocd-repositories.yaml

# 配置 ArgoCD SSH 倉庫認證（替代方案）
./scripts/setup-argocd-ssh.sh

# 部署 Root Application（App-of-Apps）
kubectl apply -f root-argocd-app.yaml

# 雙重強化檢查：ArgoCD GitOps 部署驗證
./scripts/validation-check.sh --phase9

# 驗證 Argo CD 核心組件和應用
kubectl get pods -n argocd
kubectl get applicationsets -n argocd
kubectl get applications -n argocd

# 🔧 故障排除：
# 如果 ArgoCD 無法訪問 detectviz-gitops 倉庫，請確保：
# 1. 倉庫已推送到 GitHub
# 2. GitHub App 已正確安裝到 detectviz 組織，並有 Contents 讀取權限
# 3. GitHub App 的 Installation ID 正確設置（數字 ID，不是 Client ID）
# 4. repository secret 中的所有字段都正確設置
# 5. ArgoCD repo-server 已重新啟動以應用新認證
# 6. 檢查 repo server 日誌：kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server
```

Argo CD 啟動後會自動同步下列 ApplicationSet：
- `appsets/argocd-bootstrap-app.yaml`：維護 Argo CD 自身設定。
- `appsets/appset.yaml`：部署基礎設施應用（kube-vip、MetalLB、TopoLVM、Vault、External Secrets Operator 等）。
- 其他業務相關 ApplicationSet（例如 `observability-appset.yaml`）僅在目標 repo 中存在對應 overlays 時才會同步。

> [!TIP]
> 如果 Argo CD 需存取私有 Git 倉庫，請執行 `scripts/setup-argocd-ssh.sh`，安全設置 SSH 認證。

---

## Phase 4: GitOps 管理的叢集服務驗證

Argo CD 啟動後會自動部署核心平台元件。請勿手動 `kubectl apply` 變更這些資源，改為更新對應 repo 中的 YAML。

### Kube-VIP（Control Plane VIP）
- 定義位置：`appsets/appset.yaml` → `apps/kube-vip/` overlays。
- 驗證：
  ```bash
  kubectl get pods -n kube-system -l app.kubernetes.io/name=kube-vip-ds
  ping -c 3 192.168.0.10
  ./scripts/validation-check.sh --phase3
  ./scripts/test-pod-recovery.sh
  ```

### MetalLB（Service LoadBalancer）✅ **已完成**
- 定義位置：`appsets/appset.yaml` → `apps/metallb/overlays`。
- 功能：為LoadBalancer類型Service提供外部IP地址分配
- IP範圍：192.168.0.11-192.168.0.100
- 模式：Layer 2 (本地網路廣告)
- 狀態：已成功部署，26個資源正常運行
- 驗證：
  ```bash
  # 檢查MetalLB Pod狀態
  kubectl get pods -n metallb-system

  # 檢查IP地址池
  kubectl get ipaddresspools.metallb.io -n metallb-system

  # 檢查L2廣告配置
  kubectl get l2advertisements.metallb.io -n metallb-system

  # 測試LoadBalancer功能
  kubectl apply -f - <<EOF
  apiVersion: v1
  kind: Service
  metadata:
    name: test-lb
    namespace: default
  spec:
    type: LoadBalancer
    ports:
    - port: 80
      targetPort: 8080
    selector:
      app: test
  EOF

  # 檢查是否分配了外部IP
  kubectl get svc test-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
  kubectl delete svc test-lb
  ```

### TopoLVM 與 StorageClass
- 定義位置：`appsets/appset.yaml` → `apps/topolvm/overlays`。
- 驗證：
  ```bash
  kubectl get pods -n kube-system -l app.kubernetes.io/name=topolvm
  kubectl get storageclass | grep detectviz-data
  ```

### cert-manager ✅ **已完成**
- 定義位置：`appsets/appset.yaml` → `apps/cert-manager/overlays`。
- 功能：Kubernetes 證書管理控制器，支持自動化 TLS 證書頒發和管理
- 組件：cert-manager controller、cainjector、webhook
- 狀態：已成功部署，46個資源正常運行
- 驗證：
  ```bash
  # 檢查所有組件運行狀態
  kubectl get pods -n cert-manager

  # 檢查證書資源
  kubectl get certificates -A
  kubectl get certificaterequests -A

  # 檢查集群頒發者
  kubectl get clusterissuers
  ```

### External Secrets Operator (ESO) ⏸️ **待修復**
- 定義位置：`appsets/appset.yaml` → `apps/external-secrets-operator/overlays`。
- 功能：從外部秘密存儲（如Vault、AWS Secrets Manager）同步秘密到Kubernetes
- 組件：external-secrets控制器、webhook、cert-controller
- 注意：需要Helm支持，請確保ArgoCD repo-server配置正確
- 狀態：**阻塞** - 等待解決網路連通性問題（節點無法訪問外部網路）
- 驗證：
  ```bash
  # 檢查ESO組件狀態
  kubectl get pods -n external-secrets-system

  # 檢查秘密存儲資源
  kubectl get clustersecretstores
  kubectl get externalsecrets -A

  # 檢查Vault集成（如果使用）
  kubectl get clustersecretstores vault-backend -o yaml
  ```

### Namespaces、ResourceQuota、NetworkPolicy
- 定義位置：`bootstrap/cluster-resources/`（由 `argocd-bootstrap-app` 管理）。
- 驗證：
  ```bash
  kubectl get namespaces
  kubectl get resourcequota -A
  kubectl get networkpolicies -A
  ```

---

## Phase 5: 節點標籤同步（選擇性）

Terraform 產出的 VM metadata 可透過腳本套用至 Kubernetes 節點，以利後續調度或監控。

```bash
export TF_DIR=terraform
./scripts/render-node-labels.sh > .last-node-labels.sh
bash .last-node-labels.sh

kubectl get nodes -L app.kubernetes.io/name,app.kubernetes.io/component,detectviz.io/proxmox-host
```

如需自訂標籤，請修改 Terraform 輸出或編輯產生的腳本再執行。

---

## Phase 6: Vault + External Secrets Operator 整合

Argo CD 會自動部署 Vault（`apps/vault/overlays`）與 External Secrets Operator（`apps/external-secrets-operator/overlays`），但 Vault 初始化與 Kubernetes Auth 設定仍需人工執行。

### 1. Vault 初始化與解封
```bash
kubectl exec -n vault statefulset/vault -c vault -- \
  vault operator init -key-shares=5 -key-threshold=3 > vault.init
chmod 600 vault.init

for i in 1 2 3; do
  kubectl exec -n vault statefulset/vault -c vault -- \
    vault operator unseal "$(grep "Unseal Key $i:" vault.init | awk '{print $NF}')"
done

export VAULT_TOKEN=$(grep 'Initial Root Token:' vault.init | awk '{print $NF}')
kubectl exec -n vault statefulset/vault -c vault -- vault login "$VAULT_TOKEN"
```

> [!WARNING]
> 請妥善保存 `vault.init`，完成設定後移至安全位置並從工作目錄移除。切勿將 Root Token 或 Unseal Keys 存放於 Git。

### 2. 啟用 Kubernetes Auth 並建立角色
```bash
kubectl exec -n vault statefulset/vault -c vault -- vault auth enable kubernetes

SA_JWT=$(kubectl create token vault -n vault --duration=8760h)
VAULT_CA=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt

kubectl exec -n vault statefulset/vault -c vault -- vault write auth/kubernetes/config \
  token_reviewer_jwt="$SA_JWT" \
  kubernetes_host="https://kubernetes.default.svc:443" \
  kubernetes_ca_cert=@$VAULT_CA

cat <<'POLICY' | kubectl exec -n vault -i statefulset/vault -c vault -- vault policy write external-secrets -
path "secret/data/argocd/*" {
  capabilities = ["read"]
}
path "secret/data/platform/*" {
  capabilities = ["read"]
}
POLICY

kubectl exec -n vault statefulset/vault -c vault -- vault write auth/kubernetes/role/external-secrets \
  bound_service_account_names=external-secrets \
  bound_service_account_namespaces=external-secrets-system \
  policies=external-secrets \
  ttl=24h
```

### 3. 設置 Argo CD SSH 金鑰
```bash
# 直接將 SSH 私鑰設置到 ArgoCD secret 中
SSH_KEY_PATH=~/.ssh/id_ed25519_detectviz ./scripts/setup-argocd-ssh.sh
```

此腳本會將 SSH 私鑰安全地注入到 ArgoCD 的 `detectviz-github-ssh-creds` secret 中，無需依賴 Vault 或 ESO。

### 4. 驗證 ESO 與 Vault 整合
```bash
kubectl get pods -n external-secrets-system
kubectl get clustersecretstores.external-secrets.io
kubectl get externalsecrets -A
```

若 ExternalSecret 尚未同步，請確認 Vault Policy 與 Role 設定是否與 `apps/external-secrets-operator/overlays/cluster-secret-store.yaml` 中的 `role: external-secrets` 相符。

---

## 最終驗證

```bash
./scripts/validation-check.sh --final
kubectl get nodes
kubectl get pods -A --field-selector=status.phase!=Running | grep -v topolvm || echo "✓ 只有 TopoLVM Pod Pending（若無資料磁碟為正常現象）"
kubectl get storageclass
kubectl get ingress -A
kubectl get applications -n argocd

# 確認 LoadBalancer 正常
kubectl apply -f - <<'LB'
apiVersion: v1
kind: Service
metadata:
  name: test-end-to-end
  namespace: default
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 8080
  selector:
    app: test
LB

sleep 5
kubectl get svc test-end-to-end -o jsonpath='{.status.loadBalancer.ingress[0].ip}' | grep -q "192.168.0." && echo "✓ LoadBalancer IP 分配正常" || echo "❌ LoadBalancer IP 分配失敗"
kubectl delete svc test-end-to-end
```

完成上述流程後，DetectViz 平台的基礎設施與 GitOps 控制面即告就緒，可進一步部署應用程式或進行叢集擴展。

---

## 當前部署狀態總結

| 階段 | 組件 | 狀態 | 資源數量 | 備註 |
|------|------|------|----------|------|
| ✅ **Phase 1** | **MetalLB** | 完成 | 26資源 | LoadBalancer功能正常 |
| ✅ **Phase 2** | **cert-manager** | 完成 | 46資源 | 證書管理就緒 |
| ✅ **Phase 3** | **ArgoCD** | 完成 | 12個資源 | HA模式，資源限制已配置 |
| ✅ **Phase 3** | **CNI網路** | 完成 | - | Flannel網路插件運行中 |
| ✅ **Phase 3** | **ApplicationSets** | 完成 | - | targetRevision字段已修復 |
| ⏸️ **Phase 4** | **ESO** | 阻塞 | - | **等待解決網路連通性問題** |
| ⏸️ **Phase 4** | **功能驗證** | 等待 | - | 需要網路連通性修復後進行 |

### 關鍵發現與修復

1. **✅ etcd 連接問題**: 已修復集群穩定性
2. **✅ RBAC 權限問題**: 已修復 kubernetes-admin 用戶權限
3. **✅ CNI 網路插件**: 已安裝並配置 Flannel
4. **✅ ApplicationSet Schema**: 已修復 targetRevision 字段問題
5. **❌ 網路連通性**: **關鍵阻塞問題** - 節點無法訪問外部網路，阻止容器鏡像拉取

### 下一步行動

**優先級 1 (緊急)**: 解決網路連通性問題
- 配置 NAT 或路由讓節點訪問外部網路
- 或者設置本地鏡像倉庫
- 修復後即可繼續 ESO 部署和功能驗證
