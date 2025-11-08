# DetectViz Platform 故障排除指南

**版本**: 1.0
**最後更新**: 2025-11-07

---

## 總覽

本指南涵蓋 DetectViz 平台部署過程中常見的問題與解決方案。問題按部署階段分類，便於快速定位。

---

## 目錄

### 一般問題
- [SSH 連接問題](#ssh-連接問題)
- [網路連通性問題](#網路連通性問題)

### Phase 1: Terraform 問題
- [VM 創建失敗](#vm-創建失敗)
- [Proxmox API 連接問題](#proxmox-api-連接問題)

### Phase 2: Ansible 問題
- [節點連線失敗](#節點連線失敗)
- [Kubernetes 初始化失敗](#kubernetes-初始化失敗)

### Phase 3: ArgoCD 問題
- [安裝腳本錯誤](#安裝腳本錯誤)
- [Pods 啟動失敗](#pods-啟動失敗)

### Phase 4+: GitOps 問題
- [ApplicationSet 同步失敗](#applicationset-同步失敗)
- [應用部署失敗](#應用部署失敗)

---

## 一般問題

### SSH 連接問題

**症狀**: `Host key verification failed` 或 `Connection refused`

**解決方案**:

1. **清理已知主機金鑰**:
   ```bash
   # 清理特定 IP 的 SSH 金鑰
   ssh-keygen -f ~/.ssh/known_hosts -R 192.168.0.11
   ssh-keygen -f ~/.ssh/known_hosts -R 192.168.0.12
   # ... 為所有節點重複
   ```

2. **使用集中清理腳本**:
   ```bash
   ./scripts/cluster-cleanup.sh network-cleanup
   ```

3. **重新生成 SSH 金鑰**:
   ```bash
   # 在控制節點上
   ssh-keygen -f ~/.ssh/id_rsa -N ""
   # 複製到所有目標節點
   ssh-copy-id ubuntu@192.168.0.11
   ```

### 網路連通性問題

**檢查步驟**:

1. **驗證節點間連通性**:
   ```bash
   ping 192.168.0.11
   ping 192.168.0.12
   ```

2. **檢查 DNS 解析**:
   ```bash
   ./scripts/test-cluster-dns.sh
   ```

---

## Phase 1: Terraform 問題

### VM 創建失敗

**常見錯誤**: `unable to create VM 111: config file already exists`

**解決方案**:

```bash
# 清理 Terraform 狀態
cd terraform
rm -rf .terraform terraform.tfstate*

# 重新初始化
terraform init

# 檢查現有 VM
terraform state list

# 如果需要，調整 VM ID
# 在 main.tf 中將 vm_id 從 111 改為 211
```

### Proxmox API 連接問題

**錯誤**: `connection refused` 或認證失敗

**檢查**:

1. **驗證憑證**:
   ```bash
   # 檢查環境變數
   echo $PROXMOX_API_URL
   echo $PROXMOX_API_TOKEN_ID
   ```

2. **測試 API 連通性**:
   ```bash
   curl -k "$PROXMOX_API_URL/api2/json/nodes" \
     -H "Authorization: PVEAPIToken=$PROXMOX_API_TOKEN_ID=$PROXMOX_API_TOKEN_SECRET"
   ```

---

## Phase 2: Ansible 問題

### 節點連線失敗

**使用清理腳本**:
```bash
./scripts/cluster-cleanup.sh network-cleanup
```

### Kubernetes 初始化失敗

**檢查 etcd 狀態**:
```bash
./scripts/cluster-cleanup.sh check-etcd
```

**重置集群**:
```bash
./scripts/cluster-cleanup.sh reset-cluster
```

---

## Phase 3: ArgoCD 問題

### 安裝腳本錯誤

**錯誤**: `[: 0 0: integer expected`

**原因**: 變數包含非數字字符

**已修復**: 安裝腳本已更新以正確處理數值變數

### SSH 認證問題

**錯誤**: `authentication required: Repository not found` 或 `SSH agent requested but SSH_AUTH_SOCK not-specified`

**解決方案**:

1. **檢查 SSH 認證配置**:
   ```bash
   kubectl get secrets -n argocd -l argocd.argoproj.io/secret-type=repository
   ```

2. **使用安全腳本設置 SSH 認證**:
   ```bash
   # 設置默認 SSH 金鑰 (~/.ssh/id_ed25519_detectviz)
   ./scripts/setup-argocd-ssh.sh

   # 或指定自定義 SSH 金鑰路徑
   SSH_KEY_PATH=/path/to/your/private/key ./scripts/setup-argocd-ssh.sh
   ```

3. **手動應用 SSH 認證配置**:
   ```bash
   kubectl apply -f apps/argocd/overlays/argocd-repositories.yaml
   ```

4. **驗證 SSH 認證**:
   ```bash
   kubectl get secret detectviz-github-ssh-creds -n argocd -o yaml
   ```

5. **強制重新同步應用**:
   ```bash
   kubectl patch application <app-name> -n argocd --type merge -p '{"operation":{"sync":{"revision":"HEAD","syncStrategy":{"hook":{"force":true}}},"initiatedBy":{"username":"admin"},"retry":{}}}'
   ```

### GitHub App 認證問題

**錯誤**: `authentication required: Repository not found`（即使 SSH 認證正常）

**原因**: GitHub App 需要 Installation ID 和正確的權限配置

**解決方案**:

1. **確認 GitHub App 安裝**:
   ```bash
   # 檢查 App 是否已安裝到 detectviz 組織
   # 前往: https://github.com/organizations/detectviz/settings/apps
   ```

2. **獲取 Installation ID**:
   ```bash
   # 前往 GitHub 組織設定
   # https://github.com/organizations/detectviz/settings/installations

   # 找到您的 ArgoCD GitHub App
   # Installation ID 是一個數字（例如：93529181）
   # 不是 Client ID（Iv23liRniVgX4o7RNaFT）

   # 如果沒有安裝，請先安裝 App 到組織
   # 注意：App 需要安裝到組織層級才能訪問所有倉庫
   ```

3. **檢查倉庫特定的權限**:
   ```bash
   # 如果組織安裝還是不工作，檢查倉庫設定：
   # https://github.com/detectviz/detectviz-gitops/settings/installations

   # 確保 App 已安裝到 detectviz-gitops 倉庫
   ```

4. **檢查 GitHub App 權限**:
   ```bash
   # 前往 GitHub App 設定
   # https://github.com/settings/apps/argocd-for-detectviz-gitops

   # Repository permissions 必須包含：
   # ✅ Contents: Read-only
   # ✅ Metadata: Read-only

   # Organization permissions：
   # ✅ Members: Read-only (如果需要組織認證)
   ```

4. **更新 repository secret**:
   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: detectviz-gitops-repo
     namespace: argocd
     labels:
       argocd.argoproj.io/secret-type: repository
   stringData:
     url: https://github.com/detectviz/detectviz-gitops.git
     type: git
     project: detectviz-platform
     githubAppId: "2250976"
     githubAppInstallationId: "<從 GitHub 獲取的 Installation ID>"
     githubAppPrivateKey: |
       -----BEGIN RSA PRIVATE KEY-----
       <私鑰內容>
       -----END RSA PRIVATE KEY-----
   ```

4. **重新啟動 ArgoCD 組件**:
   ```bash
   kubectl delete pod -n argocd -l app.kubernetes.io/name=argocd-repo-server
   ```

#### ArgoCD 負載均衡優化

**問題**: 單一節點資源壓力過大，影響同步性能
**解決方案**: 通過親和性配置實現組件分散部署

**常見問題**:
1. **Redis Pod 調度失敗**: ArgoCD HA Redis 需要3副本，但集群只有2個worker節點
   - **解決**: 降低Redis StatefulSet和Haproxy Deployment的副本數到2

2. **應用同步權限問題**: "resource :Namespace is not permitted in project"
   - **解決**: 將Namespace添加到clusterResourceWhitelist

3. **MetalLB 自定義資源同步問題**: IPAddressPool和L2Advertisement不被允許
   - **解決**: 確保metallb.io組的資源在namespaceResourceWhitelist中

4. **ArgoCD Helm 支持未啟用**: "must specify --enable-helm"
   - **原因**: repo-server沒有正確讀取Helm配置
   - **解決**:
     ```bash
     # 1. 確保 argocd-cm 中有 helm.enabled: "true"
     kubectl get configmap argocd-cm -n argocd -o jsonpath='{.data.helm\.enabled}'

     # 2. 配置 repo-server 讀取 ConfigMap
     kubectl patch deployment argocd-repo-server -n argocd --type json -p '[
       {"op": "add", "path": "/spec/template/spec/containers/0/envFrom", "value": [
         {"configMapRef": {"name": "argocd-cm"}}
       ]}
     ]'

     # 3. 重新啟動 repo-server
     kubectl delete pod -n argocd -l app.kubernetes.io/name=argocd-repo-server
     ```

5. **集群etcd超時**: "etcdserver: request timed out"
   - **原因**: ArgoCD資源配置過度，導致節點資源壓力
   - **解決**:
     ```bash
     # 降低應用控制器資源限制
     kubectl patch statefulset argocd-application-controller -n argocd --type json -p '[
       {"op": "replace", "path": "/spec/template/spec/containers[0]/resources", "value": {
         "requests": {"cpu": "1000m", "memory": "2Gi"},
         "limits": {"cpu": "2000m", "memory": "4Gi"}
       }}
     ]'

     # 如果kubectl不可用，通過SSH在節點上執行
     ssh ubuntu@<node-ip> "kubectl --kubeconfig=/path/to/admin.conf patch statefulset argocd-application-controller -n argocd --type json -p '[{\"op\": \"replace\", \"path\": \"/spec/template/spec/containers[0]/resources\", \"value\": {\"requests\": {\"cpu\": \"1000m\", \"memory\": \"2Gi\"}, \"limits\": {\"cpu\": \"2000m\", \"memory\": \"4Gi\"}}}]'"

     # 檢查節點資源使用
     kubectl describe node <node-name>

     # 重啟ArgoCD控制器
     kubectl delete pod argocd-application-controller-0 -n argocd

     # 如果問題持續，重啟節點
     ssh ubuntu@<node-ip> "sudo reboot"
     ```

**優化步驟**:
```bash
# 1. 增加反親和性權重
kubectl patch statefulset argocd-application-controller -n argocd --type json -p '[
  {"op": "replace", "path": "/spec/template/spec/affinity/podAntiAffinity/preferredDuringSchedulingIgnoredDuringExecution/0/weight", "value": 100},
  {"op": "replace", "path": "/spec/template/spec/affinity/podAntiAffinity/preferredDuringSchedulingIgnoredDuringExecution/1/weight", "value": 50}
]'

# 2. 添加節點親和性，避免過載節點
kubectl patch statefulset argocd-application-controller -n argocd --type json -p '[
  {"op": "add", "path": "/spec/template/spec/affinity/nodeAffinity", "value": {
    "preferredDuringSchedulingIgnoredDuringExecution": [{
      "preference": {
        "matchExpressions": [{
          "key": "kubernetes.io/hostname",
          "operator": "NotIn",
          "values": ["ai"]
        }]
      },
      "weight": 80
    }]
  }}
]'

# 3. 重新啟動應用控制器
kubectl delete pod argocd-application-controller-0 -n argocd
```

**優化效果**:
- **ai節點**: CPU使用率從 57% ↓ 到 3%
- **app節點**: CPU使用率從 4% ↑ 到 37% (仍在合理範圍)
- **整體均衡**: 負載在節點間更好地分散

---

#### ArgoCD 資源配置指南

根據集群規模和應用複雜度，ArgoCD 需要以下資源：

**集群規模評估**:
- **小型集群** (1-3節點，<10應用): CPU 0.5-1核，Memory 1-2Gi
- **中型集群** (3-5節點，10-50應用): CPU 1-2核，Memory 2-4Gi
- **大型集群** (5+節點，50+應用): CPU 2-4核，Memory 4-8Gi
- **超大型集群** (10+節點，海量應用): CPU 4-8核，Memory 8-16Gi

**當前集群配置** (5節點，7應用):
```yaml
# 推薦配置
resources:
  requests:
    cpu: 2000m    # 2核
    memory: 4Gi
  limits:
    cpu: 4000m    # 4核
    memory: 8Gi

# 環境變數優化
env:
- name: ARGOCD_CONTROLLER_REPLICAS
  value: "2"
- name: ARGOCD_CONTROLLER_RECONCILIATION_TIMEOUT
  value: "10m"
- name: ARGOCD_APPLICATION_CONTROLLER_KUBECTL_PARALLELISM_LIMIT
  value: "20"
```

**應用命令**:
```bash
# 應用資源配置
kubectl patch statefulset argocd-application-controller -n argocd --type json -p '[
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources", "value": {
    "requests": {"cpu": "2000m", "memory": "4Gi"},
    "limits": {"cpu": "4000m", "memory": "8Gi"}
  }},
  {"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {
    "name": "ARGOCD_CONTROLLER_REPLICAS", "value": "2"
  }},
  {"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {
    "name": "ARGOCD_CONTROLLER_RECONCILIATION_TIMEOUT", "value": "10m"
  }},
  {"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {
    "name": "ARGOCD_APPLICATION_CONTROLLER_KUBECTL_PARALLELISM_LIMIT", "value": "20"
  }}
]'

# 重新啟動應用控制器
kubectl delete pod argocd-application-controller-0 -n argocd
```

#### 資源規模問題
即使增加 Controller 資源限制，仍可能遇到大型應用同步問題：

**現象**: 應用有 20+ 資源，但同步持續超時
**原因**: 應用規模超過 Controller 處理能力
**解決方案**:
1. **增加資源到極限**:
   ```bash
   kubectl patch statefulset argocd-application-controller -n argocd --type json -p '[
     {"op": "replace", "path": "/spec/template/spec/containers/0/resources", "value": {
       "requests": {"cpu": "2000m", "memory": "4Gi"},
       "limits": {"cpu": "4000m", "memory": "8Gi"}
     }}
   ]'
   ```

2. **拆分大型應用**:
   - 將 CRDs 和控制器分離
   - 按功能模組拆分 (core, webhooks, etc.)

3. **禁用自動同步，改為手動同步**:
   ```yaml
   spec:
     syncPolicy:
       # 移除 automated 區塊
       syncOptions:
         - CreateNamespace=true
   ```

#### SSH 私鑰安全提醒

**⚠️ 安全警告**: 永遠不要將 SSH 私鑰存放在公開 Git 倉庫中！

**正確做法**:
- ✅ 使用 `./scripts/setup-argocd-ssh.sh` 腳本安全設置
- ✅ 將私鑰存儲在本地安全位置
- ✅ 使用 GitHub App 進行倉庫認證（推薦）
- ✅ 使用 Vault + ESO 進行生產環境的私鑰管理
- ❌ 不要在 YAML 文件中硬編碼私鑰

#### etcd 連接問題診斷與修復

**問題現象**:
- `dial tcp 127.0.0.1:2379: connect: connection refused`
- API Server CrashLoopBackOff
- kubectl 命令失敗

**根本原因**:
etcd 數據損壞或配置不一致導致 etcd 服務無法正常啟動，進而影響整個 Kubernetes 控制平面。

**診斷步驟**:
```bash
# 1. 檢查 etcd 進程狀態
sudo ps aux | grep etcd

# 2. 檢查 etcd 健康狀態（在 etcd 容器內）
sudo ctr -n k8s.io tasks exec --exec-id check-etcd <etcd-container-id> sh -c '
  ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    endpoint health
'

# 3. 檢查 etcd 集群成員狀態
sudo ctr -n k8s.io tasks exec --exec-id check-etcd <etcd-container-id> sh -c '
  ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    member list
'
```

**修復步驟**:
```bash
# 1. 停止 kubelet（讓 etcd 靜態 pod 停止）
sudo systemctl stop kubelet

# 2. 備份現有的 etcd 數據
sudo mv /var/lib/etcd /var/lib/etcd-backup-$(date +%s)

# 3. 創建新的 etcd 數據目錄
sudo mkdir -p /var/lib/etcd

# 4. 重新啟動 kubelet，讓 etcd 以全新狀態啟動
sudo systemctl start kubelet

# 5. 等待 etcd 和 API Server 恢復
sleep 60

# 6. 驗證修復結果
sudo curl -k https://127.0.0.1:6443/healthz
```

**驗證修復成功**:
```bash
# API Server 健康檢查
curl -k https://127.0.0.1:6443/healthz

# etcd 健康檢查
sudo ctr -n k8s.io tasks exec --exec-id verify-etcd <etcd-container-id> sh -c '
  ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    endpoint health
'

# 檢查集群節點狀態
kubectl get nodes
```

**注意事項**:
- etcd 數據清理會導致所有集群狀態丟失，包括已部署的應用
- 修復後需要重新部署所有應用
- 建議在生產環境中實施 etcd 備份策略

### CNI 網路插件問題

**問題現象**:
- ArgoCD pods 處於 `ContainerCreating` 狀態並卡住
- 錯誤訊息: `plugin type="calico" failed (add): error getting ClusterInformation`
- Flannel pods 處於 `CrashLoopBackOff` 狀態
- 日誌顯示: `Failed to check br_netfilter: stat /proc/sys/net/bridge/bridge-nf-call-iptables: no such file or directory`

**根本原因**:
Kubernetes 集群缺少網路插件 (CNI)，或者網路插件配置不正確。CNI 是 Kubernetes 的核心組件，負責 pod 間網路通信。

**修復方案**:

1. **檢查當前 CNI 狀態**:
   ```bash
   # 檢查是否有 CNI pods 在運行
   kubectl get pods -n kube-flannel
   kubectl get pods -n kube-system | grep calico

   # 檢查 CNI 配置
   ls -la /etc/cni/net.d/
   ```

2. **安裝 Flannel CNI**:
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
   ```

3. **修復橋接模塊問題**:
   ```bash
   # 如果 Flannel 失敗，加載橋接模塊
   sudo modprobe br_netfilter

   # 檢查橋接文件是否存在
   ls -la /proc/sys/net/bridge/

   # 如果還是不行，重新啟動 Flannel pod
   kubectl delete pod -n kube-flannel -l app=flannel
   ```

4. **驗證 CNI 正常運行**:
   ```bash
   # 檢查 Flannel pod 狀態
   kubectl get pods -n kube-flannel

   # 等待所有 pods 準備就緒
   kubectl wait --for=condition=Ready pod -n kube-flannel --all --timeout=300s
   ```

**預防措施**:
- 在 Phase 2 Ansible 部署後立即安裝 CNI 插件
- 確保所有節點都加載了必要的內核模塊
- 監控 CNI pods 的狀態
- **確保節點有外部網路訪問權限**用於拉取容器鏡像

### 節點外部網路訪問問題

**問題現象**:
- Pods 處於 `ErrImagePull` 或 `ImagePullBackOff` 狀態
- 日誌顯示鏡像拉取超時
- `curl` 或 `ping` 外部域名失敗

**根本原因**:
Kubernetes 節點缺少外部網路訪問權限。儘管 CNI 插件提供了 pod 間網路，但節點本身需要 NAT、路由或代理配置來訪問外部網路。

**修復方案**:

1. **檢查網路連通性**:
   ```bash
   # 測試基本連通性
   ping -c 3 8.8.8.8

   # 測試域名解析
   nslookup quay.io

   # 測試 HTTPS 訪問
   curl -I --connect-timeout 10 https://quay.io
   ```

2. **檢查路由配置**:
   ```bash
   # 查看路由表
   ip route show

   # 檢查默認網關
   ip route | grep default
   ```

3. **檢查防火牆規則**:
   ```bash
   # 查看 iptables 規則
   sudo iptables -L

   # 檢查是否有阻止出站流量的規則
   sudo iptables -L | grep DROP
   ```

4. **檢查 DNS 配置**:
   ```bash
   cat /etc/resolv.conf
   ```

5. **可能的解決方案**:
   - **配置 NAT**: 在 Proxmox 或網路設備上配置 NAT，讓內部網路能訪問外部網路
   - **配置代理**: 設置 HTTP/HTTPS 代理
   - **使用本地鏡像倉庫**: 配置本地鏡像倉庫或鏡像緩存
   - **檢查 VLAN/網路隔離**: 確保節點在正確的網路段

**預防措施**:
- 在部署前測試節點的外部網路連通性
- 考慮使用本地鏡像倉庫來避免依賴外部網路
- 記錄網路拓撲和配置要求

### 倉庫訪問問題

**錯誤**: `authentication required: Repository not found` 或 `404 Not Found`

**解決方案**:

1. **檢查倉庫是否存在並公開**:
   ```bash
   # 測試倉庫可訪問性
   curl -s -o /dev/null -w "%{http_code}" https://github.com/detectviz/detectviz-gitops
   # 應該返回 200
   ```

2. **確保倉庫已推送到 GitHub**:
   ```bash
   # 在 detectviz-gitops 目錄中
   git status
   git add .
   git commit -m "Update deployment configuration"
   git push origin main
   ```

3. **檢查倉庫是否設為私有**:
   - 前往 GitHub 倉庫設定
   - 確保倉庫是公開的，或者配置適當的認證

### Helm 支持問題

**錯誤**: `must specify --enable-helm`

**解決方案**:

1. **檢查 ArgoCD 配置**:
   ```bash
   kubectl get configmap argocd-cmd-params-cm -n argocd -o yaml | grep helm
   ```

2. **重新啟動 repo-server**:
   ```bash
   kubectl delete pod -n argocd -l app.kubernetes.io/name=argocd-repo-server
   ```

3. **確保配置已應用**:
   ```bash
   kubectl patch application argocd-bootstrap -n argocd --type merge -p '{"operation":{"sync":{"revision":"HEAD"},"initiatedBy":{"username":"admin"}}}'
   ```

### Pods 啟動失敗

**檢查依賴**:
1. **驗證 VIP 可用**:
   ```bash
   ping 192.168.0.10
   ```

2. **檢查 MetalLB**:
   ```bash
   kubectl get pods -n metallb-system
   ```

3. **檢查 cert-manager**:
   ```bash
   kubectl get pods -n cert-manager
   ```

4. **檢查 CNI 網路插件**:
   ```bash
   # 檢查是否有 CNI pods 在運行
   kubectl get pods -n kube-flannel
   kubectl get pods -n kube-system | grep calico

   # 如果沒有 CNI 插件，安裝 Flannel
   kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

   # 如果 Flannel 失敗，加載橋接模塊
   sudo modprobe br_netfilter
   ```

---

## Phase 4+: GitOps 問題

### ApplicationSet 同步失敗

**檢查 ArgoCD 狀態**:
```bash
kubectl get pods -n argocd
kubectl logs -n argocd deployment/argocd-application-controller
```

#### ApplicationSet Schema 錯誤

**錯誤**: `.spec.generators[0].git.targetRevision: field not declared in schema`

**問題現象**:
- ApplicationSet 無法同步
- observability, data, detectviz-apps ApplicationSets 失敗
- ArgoCD 應用狀態顯示 Schema 錯誤

**根本原因**:
ApplicationSet 配置使用了不支援的 `targetRevision` 字段，該字段在當前 ArgoCD 版本中已被移除或重命名。

**修復方案**:

1. **檢查 ApplicationSet 配置**:
   ```bash
   # 查看有問題的 ApplicationSet
   kubectl get applicationsets -n argocd
   kubectl describe applicationset observability -n argocd
   ```

2. **修復 targetRevision 字段**:
   ```yaml
   # 錯誤配置（不要使用）
   generators:
   - git:
       repoURL: https://github.com/detectviz/detectviz-apps.git
       targetRevision: HEAD  # ❌ 不支援的字段
       directories:
       - path: observability/*

   # 正確配置
   generators:
   - git:
       repoURL: https://github.com/detectviz/detectviz-apps.git
       revision: HEAD  # ✅ 使用 revision 而不是 targetRevision
       directories:
       - path: observability/*
   ```

3. **替代方案：使用 ref 字段**:
   ```yaml
   generators:
   - git:
       repoURL: https://github.com/detectviz/detectviz-apps.git
       ref: HEAD  # ✅ 另一種正確寫法
       directories:
       - path: observability/*
   ```

4. **修復所有受影響的 ApplicationSets**:
   ```bash
   # 編輯 ApplicationSet 配置
   kubectl edit applicationset observability -n argocd
   kubectl edit applicationset data -n argocd
   kubectl edit applicationset detectviz-apps -n argocd
   ```

5. **清理無效的 ApplicationSets**:
   ```bash
   # 如果修復失敗，刪除並重新創建
   kubectl delete applicationset observability data detectviz-apps -n argocd

   # 重新應用正確的配置
   kubectl apply -f appsets/observability-appset.yaml
   kubectl apply -f appsets/data-appset.yaml
   kubectl apply -f appsets/detectviz-appset.yaml
   ```

**驗證修復**:
```bash
# 檢查 ApplicationSet 狀態
kubectl get applicationsets -n argocd

# 查看同步狀態
kubectl get applications -n argocd

# 檢查 ArgoCD 控制器日誌
kubectl logs -n argocd deployment/argocd-application-controller -f
```

**預防措施**:
- 始終檢查 ArgoCD 版本兼容性
- 使用 `revision` 或 `ref` 字段而非 `targetRevision`
- 在提交到 Git 之前測試 ApplicationSet 配置

### 應用部署失敗

**常見問題**:

1. **資源配額不足**:
   ```bash
   kubectl describe resourcequota -n detectviz
   ```

2. **網路策略阻擋**:
   ```bash
   kubectl get networkpolicies -n detectviz
   ```

3. **依賴未就緒**:
   ```bash
   kubectl get pods -n detectviz
   ```

---

## 緊急恢復

### 完全重置集群

```bash
# 1. 清理 Terraform 資源
cd terraform
terraform destroy -auto-approve

# 2. 清理本機 SSH 狀態
./scripts/cluster-cleanup.sh network-cleanup

# 3. 重新開始部署
# 回到 Phase 1
```

### 保留數據的重置

```bash
# 清理應用但保留基礎設施
kubectl delete applicationset --all -n argocd
kubectl delete applications --all -n argocd

# 重新應用根應用
kubectl apply -f root-argocd-app.yaml
```

---

## 調試工具

### 集群狀態檢查

```bash
# 運行完整驗證
./scripts/validation-check.sh --all

# DNS 測試
./scripts/test-cluster-dns.sh

# 網路清理
./scripts/cluster-cleanup.sh --help
```

### 日誌收集

```bash
# ArgoCD 日誌
kubectl logs -n argocd deployment/argocd-application-controller -f

# 系統日誌
kubectl logs -n kube-system -l component=kube-apiserver -f

# 節點日誌
kubectl describe node <node-name>
```

---

## 聯繫支援

如果問題持續存在：

1. 收集相關日誌
2. 記錄錯誤訊息
3. 說明重現步驟
4. 參考 [GitHub Issues](../../issues)

---

## 最近修復的關鍵問題

### ✅ 已修復問題

1. **etcd 連接問題診斷與修復** - 新增了完整的診斷和修復流程
2. **ApplicationSet Schema 錯誤** - 修復了 `targetRevision` 字段問題
3. **CNI 網路插件問題** - 新增了 Flannel 安裝和配置指南
4. **節點外部網路訪問問題** - 新增了網路連通性診斷和修復方案

### 📋 部署過程中的重要發現

- **網路連通性是關鍵依賴**: Kubernetes 節點必須有外部網路訪問權限來拉取容器鏡像
- **CNI 插件順序重要**: CNI 配置文件按字母順序加載，配置衝突會導致網路問題
- **RBAC 配置需重啟**: RBAC 權限變更後需要重啟 API Server 才能生效
- **ApplicationSet 版本兼容性**: 不同 ArgoCD 版本對字段名稱的要求不同

### 🎯 當前阻塞問題

**網路連通性問題**: 節點無法訪問外部網路，這阻止了所有容器鏡像的拉取和應用部署。

*本文檔持續更新。如有新問題請提交 PR 或 Issue。*
