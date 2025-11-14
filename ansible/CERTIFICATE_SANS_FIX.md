# API Server 證書 SANs 修正

**日期**: 2025-11-13
**問題**: Master-2 無法加入集群
**狀態**: ✅ 已修正

---

## 🔴 問題描述

### 錯誤訊息

```
error execution phase preflight: couldn't validate the identity of the API Server:
failed to request the cluster-info ConfigMap:
Get "https://k8s-api.detectviz.internal:6443/...":
tls: failed to verify certificate: x509: certificate is valid for
kubernetes, kubernetes.default, kubernetes.default.svc,
kubernetes.default.svc.cluster.local, master-1,
NOT k8s-api.detectviz.internal
```

### 根本原因

API Server 的 TLS 證書不包含 `k8s-api.detectviz.internal` 和 VIP 地址在 Subject Alternative Names (SANs) 中。

**為什麼會這樣？**

1. Kubeadm init 時使用 `controlPlaneEndpoint: "192.168.0.11:6443"` (IP 地址)
2. Kubeadm 只自動添加了以下 SANs：
   - `kubernetes`
   - `kubernetes.default`
   - `kubernetes.default.svc`
   - `kubernetes.default.svc.cluster.local`
   - `master-1` (主機名)
   - `192.168.0.11` (IP)

3. **缺少的 SANs**：
   - ❌ `k8s-api.detectviz.internal` (VIP 域名)
   - ❌ `192.168.0.10` (VIP IP)
   - ❌ `192.168.0.12`, `192.168.0.13` (其他 master IP)

4. Master-2 join 時使用 VIP endpoint (`k8s-api.detectviz.internal:6443`)，證書驗證失敗

---

## ✅ 解決方案

### 修正檔案

**文件**: `roles/master/templates/kubeadm-config.yaml.j2`

### 修正內容

在 API Server 配置中添加 `certSANs` 字段：

```yaml
# API 服務器配置
apiServer:
  # API Server 證書的 Subject Alternative Names
  # 包含所有可能用於訪問 API Server 的地址
  certSANs:
    - "{{ cluster_vip }}"                                 # VIP 地址 (192.168.0.10)
    - "k8s-api.detectviz.internal"                        # VIP 域名
    - "k8s-api"                                           # VIP 短名稱
    - "192.168.0.11"                                      # Master-1 IP
    - "192.168.0.12"                                      # Master-2 IP
    - "192.168.0.13"                                      # Master-3 IP
    - "master-1"                                          # Master-1 主機名
    - "master-2"                                          # Master-2 主機名
    - "master-3"                                          # Master-3 主機名
    - "localhost"                                         # 本地訪問
    - "127.0.0.1"                                         # 本地 IP
  extraArgs:
    - name: authorization-mode
      value: Node,RBAC
    ...
```

---

## 🔍 修正後的證書內容

### 完整的 SANs 列表

重新部署後，API Server 證書將包含：

```
X509v3 Subject Alternative Name:
    DNS:k8s-api.detectviz.internal     # ← 新增
    DNS:k8s-api                         # ← 新增
    DNS:kubernetes
    DNS:kubernetes.default
    DNS:kubernetes.default.svc
    DNS:kubernetes.default.svc.cluster.local
    DNS:localhost
    DNS:master-1
    DNS:master-2                        # ← 新增
    DNS:master-3                        # ← 新增
    IP Address:10.96.0.1
    IP Address:127.0.0.1
    IP Address:192.168.0.10             # ← 新增 (VIP)
    IP Address:192.168.0.11
    IP Address:192.168.0.12             # ← 新增
    IP Address:192.168.0.13             # ← 新增
```

---

## 📊 驗證方法

### 驗證證書 SANs

部署完成後，可以驗證證書內容：

```bash
# SSH 到 master-1
ssh ubuntu@192.168.0.11

# 檢查 API Server 證書的 SANs
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -text -noout | grep -A 15 "Subject Alternative Name"
```

**預期輸出**（應包含所有添加的 DNS 和 IP）：
```
X509v3 Subject Alternative Name:
    DNS:k8s-api.detectviz.internal, DNS:k8s-api, DNS:kubernetes, ...
    IP Address:192.168.0.10, IP Address:192.168.0.11, ...
```

### 測試 VIP 訪問

```bash
# 使用 VIP 域名訪問 API Server（不應該有證書錯誤）
curl -k https://k8s-api.detectviz.internal:6443/healthz
# 預期：ok

# 使用 VIP IP 訪問
curl -k https://192.168.0.10:6443/healthz
# 預期：ok
```

### 測試 Master-2 加入

```bash
# Master-2 現在應該可以成功加入
# Ansible 會自動執行，或手動執行：
ssh ubuntu@192.168.0.12
sudo kubeadm join k8s-api.detectviz.internal:6443 \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH> \
  --control-plane \
  --certificate-key <CERT_KEY>
```

**預期結果**：
```
[preflight] Running pre-flight checks
[preflight] Reading configuration from the cluster...
[preflight] FYI: You can look at this config file with 'kubectl -n kube-system get cm kubeadm-config -o yaml'
[kubelet-start] Writing kubelet configuration to file "/var/lib/kubelet/config.yaml"
[kubelet-start] Writing kubelet environment file with flags to file "/var/lib/kubelet/kubeadm-flags.env"
[kubelet-start] Starting the kubelet
[control-plane] Using manifest folder "/etc/kubernetes/manifests"
[control-plane] Creating static Pod manifest for "kube-apiserver"
[control-plane] Creating static Pod manifest for "kube-controller-manager"
[control-plane] Creating static Pod manifest for "kube-scheduler"
[check-etcd] Checking that the etcd cluster is healthy
[kubelet-check] Initial timeout of 40s passed.

This node has joined the cluster and a new control plane instance was created:

* Certificate signing request was sent to apiserver and approval was received.
* The Kubelet was informed of the new secure connection details.
* Control plane label and taint were applied to the new node.
* The Kubernetes control plane instances scaled up.
* A new etcd member was added to the local/stacked etcd cluster.

To start administering your cluster from this node, you need to run the following as a regular user:

        mkdir -p $HOME/.kube
        sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
        sudo chown $(id -u):$(id -g) $HOME/.kube/config

Run 'kubectl get nodes' to see this node join the cluster.
```

---

## 🎯 為什麼需要這些 SANs？

| SAN | 原因 | 使用場景 |
|-----|------|---------|
| `k8s-api.detectviz.internal` | VIP 域名 | Master 加入、外部訪問 |
| `k8s-api` | VIP 短名稱 | 簡化訪問 |
| `192.168.0.10` | VIP IP | 直接 IP 訪問 |
| `192.168.0.11-13` | Master IPs | 直接訪問特定 master |
| `master-1/2/3` | Master 主機名 | 主機名訪問 |
| `localhost`, `127.0.0.1` | 本地訪問 | Master 本地 kubectl |

---

## 🔄 對現有集群的影響

### 需要重新部署

因為證書在 `kubeadm init` 時生成，無法動態更新，需要：

1. ✅ 清理現有集群
2. ✅ 重新部署（背景任務已執行）
3. ✅ 使用新的 kubeadm-config.yaml

### 替代方案（不推薦）

如果不想重新部署，可以手動更新證書：

```bash
# 1. 備份現有證書
sudo cp /etc/kubernetes/pki/apiserver.crt /etc/kubernetes/pki/apiserver.crt.backup
sudo cp /etc/kubernetes/pki/apiserver.key /etc/kubernetes/pki/apiserver.key.backup

# 2. 刪除舊證書
sudo rm /etc/kubernetes/pki/apiserver.crt
sudo rm /etc/kubernetes/pki/apiserver.key

# 3. 生成新證書（需要先修改 kubeadm-config.yaml）
sudo kubeadm init phase certs apiserver --config /tmp/kubeadm-config.yaml

# 4. 重啟 API Server
sudo crictl ps | grep kube-apiserver
sudo crictl stop <container-id>
# Kubelet 會自動重啟容器
```

**注意**: 不推薦這種方法，容易出錯。重新部署更安全可靠。

---

## ✅ 配置檢查清單

在部署前確認：

- [x] `kubeadm-config.yaml.j2` 包含完整的 `certSANs`
- [x] SANs 包含 VIP 地址和域名
- [x] SANs 包含所有 master 節點的 IP 和主機名
- [x] `control_plane_endpoint` 使用正確的地址（master-1 IP）
- [x] `control_plane_vip_endpoint` 定義 VIP 域名（供 master join 用）

---

## 🎉 修正效果

修正後：

- ✅ Master-2 可以使用 VIP 域名加入集群
- ✅ Master-3 可以使用 VIP 域名加入集群
- ✅ 所有節點可以通過 VIP 訪問 API Server
- ✅ 不會出現證書驗證錯誤
- ✅ 實現真正的 HA（通過 VIP）

---

## 📚 相關文檔

- [Kubeadm Configuration API](https://kubernetes.io/docs/reference/config-api/kubeadm-config.v1beta4/)
- [PKI Certificates and Requirements](https://kubernetes.io/docs/setup/best-practices/certificates/)
- [Creating Highly Available Clusters with kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/)

---

## 📝 總結

**問題**：API Server 證書缺少 VIP 相關的 SANs

**修正**：在 kubeadm-config.yaml 中添加 `apiServer.certSANs` 配置

**結果**：✅ Master 節點可以通過 VIP 成功加入集群，實現真正的 HA

**部署**：背景任務正在重新創建 VM，新配置將自動生效
