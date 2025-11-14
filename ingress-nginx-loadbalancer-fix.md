# Ingress-Nginx LoadBalancer 配置修復總結

**日期**: 2025-11-14 23:52
**狀態**: ✅ 完全修復

---

## 🎯 問題描述

### 症狀
無法訪問 https://argocd.detectviz.internal,ingress-nginx-controller 服務狀態為 `<pending>`,沒有分配到 EXTERNAL-IP。

### 影響
- 所有通過 Ingress 暴露的服務都無法訪問
- ArgoCD UI 無法通過域名訪問
- MetalLB LoadBalancer 無法正常工作

---

## 🔍 根本原因分析

### 問題 1: MetalLB IP 池配置不完整
**發現**: MetalLB IPAddressPool 只有 `192.168.0.200-192.168.0.220`,沒有包含 `192.168.0.10`

**證據**:
```yaml
# 原始配置
spec:
  addresses:
    - 192.168.0.200-192.168.0.220  # ❌ 缺少 .10
```

**修復**: 添加 `192.168.0.10/32` 到 IP 池
```yaml
spec:
  addresses:
    - 192.168.0.10/32  # ✅ 新增
    - 192.168.0.200-192.168.0.220
```

**文件**: `argocd/apps/infrastructure/metallb/overlays/ipaddresspool.yaml`
**Commit**: `bbab4f2` - "fix: Add 192.168.0.10 to MetalLB IP pool for ingress-nginx VIP"

---

### 問題 2: 同時使用 annotation 和 spec.loadBalancerIP
**發現**: 服務同時定義了 `metallb.universe.tf/loadBalancerIPs` 註解和 `spec.loadBalancerIP` 欄位

**MetalLB 錯誤日誌**:
```
service can not have both metallb.universe.tf/loadBalancerIPs and svc.Spec.LoadBalancerIP
```

**修復**: 移除 deprecated 的 `spec.loadBalancerIP` 欄位
```yaml
# 移除這一行:
# loadBalancerIP: 192.168.0.10
```

**Commit**: `16bb52d` - "fix: Remove deprecated loadBalancerIP field from ingress-nginx service"

---

### 問題 3: externalTrafficPolicy=Local 導致 IP 被撤回
**發現**: MetalLB speaker 日誌顯示先宣告 IP,然後立即撤回

**MetalLB 日誌**:
```
15:41:50 - "service has IP, announcing" ips=["192.168.0.10"]
15:41:50 - "withdrawing service announcement" reason="noIPAllocated"
```

**根本原因**:
- `externalTrafficPolicy: Local` 模式要求健康檢查通過
- MetalLB 通過 `healthCheckNodePort` (30511) 檢查服務健康性
- 健康檢查失敗導致 MetalLB 認為服務沒有 IP allocated

**修復**: 改用 `externalTrafficPolicy: Cluster` 模式
```yaml
spec:
  externalTrafficPolicy: Cluster  # 改為 Cluster 模式
```

**Commit**: `8bafac7` - "fix: Configure ingress-nginx LoadBalancer with externalTrafficPolicy=Cluster"

---

### 問題 4: 移除 patch 導致服務無法創建
**發現**: 嘗試只通過 Helm values.yaml 配置服務,移除 `ingress-nginx-service.yaml` patch,導致服務被刪除後無法重新創建

**根本原因**:
- Ingress-nginx 使用 Kustomize + Helm chart 部署
- Helm chart 生成的服務需要通過 strategic merge patch 覆蓋配置
- 移除 patch 後,ArgoCD 同步陷入死鎖 - 等待一個它應該創建但沒有創建的服務

**修復**: 重新添加 `ingress-nginx-service.yaml` patch,但不包含 MetalLB 特定註解
```yaml
# ingress-nginx-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
spec:
  type: LoadBalancer
  externalTrafficPolicy: Cluster  # ✅ 關鍵修復
  # 不添加 MetalLB annotations,讓 MetalLB 自動分配
```

**Commit**: `959332d` - "fix: Re-add ingress-nginx-service.yaml with correct externalTrafficPolicy"

---

## ✅ 解決方案實施

### 最終工作配置

**1. MetalLB IP 池** (`argocd/apps/infrastructure/metallb/overlays/ipaddresspool.yaml`):
```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
    - 192.168.0.10/32  # Ingress Controller VIP
    - 192.168.0.200-192.168.0.220  # 動態 IP 池
```

**2. Ingress-Nginx Service** (`argocd/apps/infrastructure/ingress-nginx/overlays/ingress-nginx-service.yaml`):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
spec:
  type: LoadBalancer
  externalTrafficPolicy: Cluster  # ✅ Cluster 模式
  ports:
    - name: http
      port: 80
      protocol: TCP
      targetPort: http
    - name: https
      port: 443
      protocol: TCP
      targetPort: https
  selector:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/instance: ingress-nginx
    app.kubernetes.io/component: controller
```

**3. Helm Values** (`argocd/apps/infrastructure/ingress-nginx/overlays/values.yaml`):
```yaml
ingress-nginx:
  controller:
    service:
      enabled: true
      type: LoadBalancer
      externalTrafficPolicy: Cluster  # 與 patch 一致
```

---

## 📊 驗證結果

### Service 狀態
```bash
$ kubectl get svc ingress-nginx-controller -n ingress-nginx

NAME                       TYPE           CLUSTER-IP       EXTERNAL-IP    PORT(S)
ingress-nginx-controller   LoadBalancer   10.110.211.240   192.168.0.10   80:31836/TCP,443:30675/TCP
```
✅ **EXTERNAL-IP 成功分配: 192.168.0.10**

### Ingress 狀態
```bash
$ kubectl get ingress -n argocd argocd-server

NAME            CLASS   HOSTS                       ADDRESS        PORTS
argocd-server   nginx   argocd.detectviz.internal   192.168.0.10   80, 443
```
✅ **ADDRESS 正確指向 192.168.0.10**

### HTTPS 連接測試
```bash
$ curl -k -I https://argocd.detectviz.internal

HTTP/2 307
date: Fri, 14 Nov 2025 15:52:05 GMT
location: https://argocd.detectviz.internal/
strict-transport-security: max-age=31536000; includeSubDomains
```
✅ **HTTPS 正常響應,返回 ArgoCD 重定向**

### MetalLB Speaker 日誌
```
2025-11-14T15:50:XX "service has IP, announcing" ips=["192.168.0.10"]
```
✅ **MetalLB 成功宣告 IP,沒有撤回**

---

## 🎓 技術洞察

### externalTrafficPolicy 模式對比

| 特性 | Local | Cluster |
|-----|-------|---------|
| 保留源 IP | ✅ 是 | ❌ 否 (SNAT) |
| 負載均衡 | 僅本地 Pod | 全集群 Pod |
| 健康檢查 | 需要 healthCheckNodePort | 不需要 |
| MetalLB 相容性 | ⚠️ 需要健康檢查通過 | ✅ 無額外要求 |
| 適用場景 | 生產環境,需要源 IP | 測試/開發環境 |

**為何選擇 Cluster 模式**:
- ✅ 避免 MetalLB L2 模式下的健康檢查問題
- ✅ 更簡單的配置,無需額外的健康檢查設置
- ⚠️ 缺點: 無法保留客戶端源 IP (Ingress 通常不需要)

### Kustomize + Helm 的最佳實踐

**不要這樣做**:
```yaml
# ❌ 嘗試只通過 values.yaml 覆蓋服務配置
# 結果: Helm chart 生成的服務可能無法被正確管理
helmCharts:
  - valuesFile: values.yaml
```

**應該這樣做**:
```yaml
# ✅ 使用 strategic merge patch 明確覆蓋
helmCharts:
  - valuesFile: values.yaml

patchesStrategicMerge:
  - ingress-nginx-service.yaml  # 明確的服務配置
```

**原因**:
- Helm chart 的默認值可能與需求不完全匹配
- Strategic merge patch 提供明確、可追蹤的覆蓋
- 避免 ArgoCD 同步時的模糊性和衝突

---

## 📋 相關 Git Commits

| Commit | 標題 | 說明 |
|--------|------|------|
| `bbab4f2` | fix: Add 192.168.0.10 to MetalLB IP pool | 添加 VIP 到 IP 池 |
| `16bb52d` | fix: Remove deprecated loadBalancerIP field | 移除 deprecated 欄位 |
| `8bafac7` | fix: Configure externalTrafficPolicy=Cluster | 改用 Cluster 模式 |
| `959332d` | fix: Re-add ingress-nginx-service.yaml | 重新添加正確的 patch |

---

## 🚀 後續改進建議

### 1. 考慮在生產環境使用 Local 模式
如果需要保留源 IP:
```yaml
externalTrafficPolicy: Local
```
並確保:
- 配置正確的 `healthCheckNodePort`
- MetalLB BGP 模式 (代替 L2 模式)
- 或者使用 NodePort externalTrafficPolicy

### 2. 監控 MetalLB 狀態
添加監控:
```bash
kubectl logs -n metallb-system -l app=metallb,component=speaker -f
kubectl logs -n metallb-system -l app=metallb,component=controller -f
```

### 3. 文檔化 LoadBalancer IP 分配策略
在 `deploy.md` 中記錄:
- IP 池範圍和用途
- LoadBalancer 服務的配置要求
- MetalLB 模式選擇指南

---

## ✅ 結論

**問題**: Ingress-Nginx LoadBalancer 服務無法分配 EXTERNAL-IP
**狀態**: ✅ **完全解決**

**關鍵修復**:
1. ✅ 添加 192.168.0.10 到 MetalLB IP 池
2. ✅ 移除 deprecated `spec.loadBalancerIP` 欄位
3. ✅ 改用 `externalTrafficPolicy: Cluster` 避免健康檢查問題
4. ✅ 使用 strategic merge patch 正確覆蓋 Helm chart 配置

**最終結果**:
- ✅ EXTERNAL-IP: 192.168.0.10 成功分配
- ✅ HTTPS 正常訪問: https://argocd.detectviz.internal
- ✅ MetalLB 穩定運行,無 IP 撤回問題
- ✅ Ingress 資源正常工作

**測試狀態**:
- Ping 192.168.0.10: ✅ 成功
- DNS 解析 argocd.detectviz.internal: ✅ 成功
- HTTPS 連接: ✅ 成功 (HTTP/2 307 重定向)
- ArgoCD UI 訪問: ✅ 可用

🎉 Ingress-Nginx LoadBalancer 現在完全正常工作!
