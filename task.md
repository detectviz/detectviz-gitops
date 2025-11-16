## kube-vip 修正配置

1. 直接 Patch Ansible（移除 DaemonSet）

```
移除 kube-vip-ds.yaml.j2，只保留 static pod
```

2. 直接 Patch ArgoCD（新增 kube-vip DaemonSet ApplicationSet）

```
argocd/apps/infrastructure/kube-vip/***.yaml
```

3. 區分「bootstrap 與 runtime」兩層 manifest

（這是 CNCF GitOps 最佳實踐）

### 架構分工（重要）

| 功能 | 由 Ansible 管理 | 由 ArgoCD 管理 |
| --- | --- | --- |
| Control Plane VIP（kubeadm bootstrap 必備） | ✔ 靜態 Pod `/etc/kubernetes/manifests/kube-vip.yaml` | ✘ 不可 |
| Worker-side VIP 管理 | ✘ | ✔ DaemonSet |
| BGP / ARP Load Balancer | ✘ | ✔ DaemonSet |
| HA API Access（VIP） | ✔ | ✘ |
| Kubeadm join 控制平面 | ✔ 依賴 VIP | ✘ |
| GitOps Lifecycle | ✘ | ✔ |

* * *

### **1. 保留 Ansible 的 kube-vip-static-pod.yaml.j2**

此為 boot-time 必要項。

### **2. 移除 Ansible 的 kube-vip-ds.yaml.j2**

因為它不屬於 bootstrap layer，可以移到 GitOps。

### **3. Argo CD 中的 Kube-VIP DaemonSet 要保留**

但你需標記清楚：

```
argocd/apps/infrastructure/kube-vip/
  ├── ds.yaml
  ├── configmap.yaml
  └── values.yaml
```

讓它僅作用於 workers / load balancer 功能，而不是 control plane。



## Calico 修正配置

1. 調整 Calico manifest（VXLAN MTU → 1450）
2. 加入 FelixConfiguration（mtu=1450）    
3. 加入 kubeadm-config 設定  
4. 加入 kube-vip MTU 
5. 加入 Ansible 變數 `network_mtu: 1500` 的動態引用

目前的 `ansible/group_vars/all.yml` 內容顯示：

```yaml
cni_provider: "calico"
calico_manifest_url: "https://raw.githubusercontent.com/projectcalico/calico/v3.27.3/manifests/calico.yaml"
calico_manifest_local_path: "/tmp/calico-patched.yaml"
```

這代表 **Calico 是由 Ansible（Bootstrap Layer）負責部署，而不是 GitOps 控制**。  
這是符合 CNCF / Kubernetes Bootstrap 最佳實踐的。

| 項目 | 是否已做 | 說明 |
| --- | --- | --- |
| 修補 Calico VXLAN MTU | ✗ | 預設 1500，不符合 overlay 網路要求 |
| kubelet network-plugin-mtu 設定 | ✗ | 必須設定為實際 CNI MTU |
| kube-vip MTU 設定 | ✗ | static pod 未配置 |
| FelixConfiguration.mtu 設定 | ✗ | 必須同步 CNI MTU |
| Calico node DaemonSet MTU patch | ✗ | 需 patch env 參數 |

以下是你目前的 **ansible/roles/master/tasks/main.yml** 檔案中，與 **network_mtu=1500**（或 MTU 設定流程相關）實際做到的項目整理。

### **✓ containerd 重啟與 sandbox image 驗證**

雖然不是 MTU 配置本身，但與 Pod 網路正常啟動密切相關：

```yaml
- name: Restart containerd to apply new sandbox image
- name: Verify containerd configuration
- name: Check containerd sandbox image
```

這影響 Pod overlay 發出的封包大小與 node-to-node networking quality。

* * *

### **✓ Calico CNI 安裝（但未設定 MTU）**

你目前下載並套用了原始 Calico manifest：

```yaml
- name: "[P2] Download Calico Manifest"
- name: "[P2] Modify Calico Manifest with Pod CIDR"
- name: "[P2] Apply Calico CNI"
```

但是這裡 **只有改 IPPool (CALICO_IPV4POOL_CIDR)**  
**沒有改 Calico MTU**，預設為 1500，且會導致 VXLAN 封包 fragmentation。

這是最重要的缺失項（後面會說明如何補齊）。

* * *

### **✓ kube-vip 靜態 Pod**

Kube-VIP 使用哪一張介面（eth0），間接與 MTU 有關，但未設定 MTU：

```yaml
- kube-vip-static-pod.yaml.j2
```

沒有任何 MTU 參數傳入。

* * *

### **✓ 生成 kubeadm bootstrap config 但未包含 MTU**

kubeadm-config.yaml.j2 目前：

* 沒有 `kubeProxyConfiguration`
    
* 沒有 `nodeRegistration.kubeletExtraArgs` 中的 `network-plugin-mtu`
    
* 沒有 CNI extra args
    

**→ kubelet 的 MTU 100% 未正確設置**

* * *


### **✗ 未設定 Calico MTU**

Calico 官方建議 MTU：

* host-device (vmbr0) → **1500 或 9000**（依你的環境）
    
* VXLAN overlay → **host MTU - 50 bytes**
    

你的環境最後採：

```
network_mtu = 1500
overlay_mtu = 1450
```

但 manifest 中沒有 patch：

```
            - name: FELIX_IPINIPMTU
              value: "1450"
            - name: FELIX_VXLANMTU
              value: "1450"
```

* * *

### **✗ kube-vip 沒有設定 MTU**

Kube-VIP yaml 中可設定介面：

```
vip_interface: "eth0"
mtu: 1500
```

目前未配置。

* * *

### **✗ Calico 未調整 FelixConfiguration**

應該加入：

```
apiVersion: operator.tigera.io/v1
kind: FelixConfiguration
metadata:
  name: default
spec:
  mtu: 1450
```

未配置。

* * *

### **✗ kubelet 沒有設定 CNI/MTU 引數**

需要 patch kubeadm：

```
nodeRegistration:
  kubeletExtraArgs:
    network-plugin-mtu: "1500"
```

目前未配置。
