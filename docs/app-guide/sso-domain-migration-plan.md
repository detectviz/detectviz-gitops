# SSO 整合與域名遷移實施計劃

**創建日期**: 2025-11-17
**狀態**: 規劃中
**優先級**: 中 (Phase 6.5 完成後實施)

---

## 📋 需求概述

### 需求 1: 統一 SSO 登入 (Keycloak)
- **目標**: Grafana 和 ArgoCD 都使用 Keycloak 進行統一身份認證
- **當前狀態**:
  - ✅ **Grafana**: 已配置 Keycloak OAuth2 (Generic OAuth)
  - ⚠️ **ArgoCD**: 當前使用 GitHub SSO (via Dex)，**需要遷移**

### 需求 2: Grafana 域名變更
- **目標**: 將 Grafana 域名從內部域名改為公網域名
- **變更**: `grafana.detectviz.internal` → `grafana.detectviz.com`
- **影響範圍**:
  - Grafana Ingress 配置
  - Grafana server domain 配置
  - Keycloak OAuth2 redirect URIs
  - DNS 配置 (需要公網 DNS 或 hosts 配置)

---

## 🎯 實施階段

### Phase A: ArgoCD Keycloak SSO 整合 (Phase 6.5+)

**時機**: Phase 6 應用部署完成，Keycloak 運行後

**準備條件**:
- ✅ Keycloak 部署完成
- ✅ Keycloak Realm 創建 (`detectviz`)
- ⚠️ 需要配置 ArgoCD OAuth2 Client

#### A.1 在 Keycloak 創建 ArgoCD Client

**操作**: Keycloak Admin Console

1. **創建 Client**:
   - Client ID: `argocd`
   - Client Protocol: `openid-connect`
   - Access Type: `confidential`
   - Valid Redirect URIs:
     - `https://argocd.detectviz.internal/auth/callback`
     - `https://argocd.detectviz.internal/api/dex/callback` (Dex fallback)
   - Web Origins: `https://argocd.detectviz.internal`

2. **配置 Client Scopes**:
   - 啟用 scopes: `openid`, `profile`, `email`, `groups`

3. **獲取 Client Secret**:
   ```bash
   # 在 Keycloak Admin UI 的 Credentials tab 獲取
   # 或使用 API
   ```

4. **儲存 Secret 到 Vault**:
   ```bash
   vault kv put secret/argocd/oauth \
     keycloak-client-secret="<從 Keycloak 複製>"
   ```

#### A.2 配置 ArgoCD OIDC (方案選擇)

**方案 A: 使用 Dex + Keycloak Connector** (推薦，保持架構一致)

**優點**:
- 保持 Dex 作為中間層，未來可輕鬆添加其他 IdP
- 無需大幅修改現有配置
- Dex 提供額外的 token 管理功能

**檔案**: `argocd/apps/infrastructure/argocd/overlays/argocd-cm.yaml`

**修改**:
```yaml
data:
  url: https://argocd.detectviz.internal

  dex.config: |
    issuer: https://argocd.detectviz.internal/api/dex
    storage:
      type: memory
    web:
      http: 0.0.0.0:5556
    connectors:
    # 保留 GitHub connector (可選，作為備用)
    - type: github
      id: github
      name: GitHub
      config:
        clientID: Iv23liRniVgX4o7RNaFT
        clientSecret: $dex.github.clientSecret
        redirectURI: https://argocd.detectviz.internal/api/dex/callback
        orgs:
        - name: detectviz

    # 新增 Keycloak connector (主要登入方式)
    - type: oidc
      id: keycloak
      name: Keycloak SSO
      config:
        issuer: https://keycloak.detectviz.internal/realms/detectviz
        clientID: argocd
        clientSecret: $dex.keycloak.clientSecret
        redirectURI: https://argocd.detectviz.internal/api/dex/callback
        scopes:
          - openid
          - profile
          - email
          - groups
        # Keycloak 特定配置
        getUserInfo: true
        insecureSkipEmailVerified: false
        # 將 Keycloak roles 映射為 groups
        claimMapping:
          groups: roles
```

**ExternalSecret 配置**:

創建 `argocd/apps/infrastructure/argocd/overlays/externalsecret-keycloak.yaml`:
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: argocd-keycloak-oauth
  namespace: argocd
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: vault-backend
  target:
    name: argocd-secret
    creationPolicy: Merge  # 合併到現有 argocd-secret
    template:
      data:
        dex.keycloak.clientSecret: "{{ .keycloakClientSecret }}"
  data:
    - secretKey: keycloakClientSecret
      remoteRef:
        key: secret/data/argocd/oauth
        property: keycloak-client-secret
```

---

**方案 B: 直接 OIDC (不使用 Dex)**

**優點**:
- 減少中間層，架構更簡單
- 直接與 Keycloak 整合

**缺點**:
- 失去 Dex 的靈活性
- 需要更多配置修改

**檔案**: `argocd/apps/infrastructure/argocd/overlays/argocd-cm.yaml`

**修改**:
```yaml
data:
  url: https://argocd.detectviz.internal

  # 禁用 Dex
  # dex.config: ...  # 註解掉

  # 啟用 OIDC
  oidc.config: |
    name: Keycloak
    issuer: https://keycloak.detectviz.internal/realms/detectviz
    clientID: argocd
    clientSecret: $oidc.keycloak.clientSecret
    requestedScopes: ["openid", "profile", "email", "groups"]
    requestedIDTokenClaims:
      groups:
        essential: true
```

**推薦**: 使用 **方案 A (Dex + Keycloak)**，保持架構一致性。

#### A.3 配置 ArgoCD RBAC

**檔案**: `argocd/apps/infrastructure/argocd/overlays/argocd-rbac-cm.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  # 預設策略: 拒絕所有未明確授權的操作
  policy.default: role:readonly

  # RBAC 策略
  policy.csv: |
    # Keycloak roles 映射
    # Admin role (from Keycloak 'admin' role)
    g, admin, role:admin

    # Editor role (from Keycloak 'editor' role)
    p, role:editor, applications, *, */*, allow
    p, role:editor, clusters, get, *, allow
    p, role:editor, repositories, get, *, allow
    p, role:editor, repositories, create, *, allow
    p, role:editor, repositories, update, *, allow
    p, role:editor, repositories, delete, *, allow
    g, editor, role:editor

    # Viewer role (from Keycloak 'viewer' role)
    p, role:viewer, applications, get, */*, allow
    p, role:viewer, clusters, get, *, allow
    p, role:viewer, repositories, get, *, allow
    g, viewer, role:viewer

    # 允許特定用戶為 admin (可選，備用管理員)
    g, admin@detectviz.com, role:admin

  # Scopes 配置
  scopes: '[groups, email]'
```

#### A.4 驗證 ArgoCD SSO

1. **重啟 ArgoCD**:
   ```bash
   kubectl rollout restart deployment argocd-server -n argocd
   kubectl rollout restart deployment argocd-dex-server -n argocd  # 如果使用 Dex
   ```

2. **測試登入**:
   - 訪問: `https://argocd.detectviz.internal`
   - 點擊 "LOG IN VIA KEYCLOAK SSO"
   - 應該重定向到 Keycloak 登入頁面
   - 登入後重定向回 ArgoCD

3. **驗證 RBAC**:
   ```bash
   # 檢查用戶權限
   argocd account get-user-info
   ```

---

### Phase B: Grafana 域名遷移 (Phase 6.5+)

**時機**: Phase 6 應用部署完成後，或與 Phase A 同步進行

**準備條件**:
- ⚠️ DNS 配置 (`grafana.detectviz.com` → 192.168.0.10 或公網 IP)
- ⚠️ TLS 證書 (Let's Encrypt 或自簽名)
- ✅ Ingress Controller 運行

#### B.1 DNS 配置 (外部依賴)

**選項 1: 公網 DNS** (推薦，如果有公網 IP)
```bash
# 在 DNS 提供商 (Cloudflare, Route53, etc.) 創建 A 記錄
# grafana.detectviz.com → <公網 IP>
```

**選項 2: 本地 DNS / hosts** (開發/內網環境)
```bash
# 在 dnsmasq (192.168.0.2) 添加
echo "address=/grafana.detectviz.com/192.168.0.10" >> /etc/dnsmasq.d/detectviz.conf
systemctl restart dnsmasq

# 或在客戶端 /etc/hosts 添加
echo "192.168.0.10 grafana.detectviz.com" >> /etc/hosts
```

#### B.2 更新 Keycloak OAuth Client

**操作**: Keycloak Admin Console

1. 編輯 `grafana` Client
2. 更新 **Valid Redirect URIs**:
   - 添加: `https://grafana.detectviz.com/*`
   - 保留舊的 (過渡期): `https://grafana.detectviz.internal/*`
3. 更新 **Web Origins**:
   - 添加: `https://grafana.detectviz.com`

#### B.3 更新 Grafana 配置

**檔案**: `argocd/apps/observability/grafana/overlays/values.yaml`

**修改 1**: 更新環境變數 (lines 218-221)
```yaml
env:
  # ... 其他環境變數 ...
  - name: GF_SERVER_DOMAIN
    value: grafana.detectviz.com  # ✅ 從 grafana.detectviz.internal 改為 grafana.detectviz.com
  - name: GF_SERVER_ROOT_URL
    value: "%(protocol)s://%(domain)s/"
```

**修改 2**: 更新 grafana.ini (lines 386-387)
```yaml
grafana.ini:
  server:
    protocol: http
    http_port: 3000
    enable_gzip: true
    domain: grafana.detectviz.com  # ✅ 從 grafana.detectviz.internal 改為 grafana.detectviz.com
    root_url: "%(protocol)s://%(domain)s/"
```

**修改 3**: 更新 OAuth URLs (lines 419-421)
```yaml
  auth.generic_oauth:
    enabled: true
    name: Keycloak
    # ... 其他配置 ...
    auth_url: https://keycloak.detectviz.com/realms/detectviz/protocol/openid-connect/auth  # ✅ 如果 Keycloak 也遷移
    token_url: https://keycloak.detectviz.com/realms/detectviz/protocol/openid-connect/token
    api_url: https://keycloak.detectviz.com/realms/detectviz/protocol/openid-connect/userinfo
    # 或保持 .internal (如果 Keycloak 不公開)
    # auth_url: https://keycloak.detectviz.internal/realms/detectviz/protocol/openid-connect/auth
```

#### B.4 創建 Grafana Ingress

**創建檔案**: `argocd/apps/observability/grafana/overlays/ingress.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana
  namespace: grafana
  annotations:
    # Nginx Ingress 配置
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"

    # TLS 配置
    cert-manager.io/cluster-issuer: "letsencrypt-prod"  # 或 "selfsigned-issuer"

    # 代理配置
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "600"

    # WebSocket 支持 (Grafana Live)
    nginx.ingress.kubernetes.io/proxy-http-version: "1.1"
    nginx.ingress.kubernetes.io/proxy-set-headers: |
      Upgrade $http_upgrade
      Connection "upgrade"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - grafana.detectviz.com
      secretName: grafana-tls  # cert-manager 自動生成
  rules:
    - host: grafana.detectviz.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: grafana
                port:
                  number: 80
```

**更新 Kustomization**: `argocd/apps/observability/grafana/overlays/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: grafana

resources:
  - ../base
  - externalsecret-admin.yaml
  - externalsecret-db.yaml
  - externalsecret-oauth.yaml
  - ingress.yaml  # ✅ 新增

helmCharts:
  - name: grafana
    valuesFile: values.yaml
```

#### B.5 部署與驗證

1. **提交變更**:
   ```bash
   git add argocd/apps/observability/grafana/overlays/
   git commit -m "Migrate Grafana domain to detectviz.com"
   git push
   ```

2. **同步 ArgoCD**:
   ```bash
   argocd app sync grafana
   ```

3. **驗證 DNS**:
   ```bash
   nslookup grafana.detectviz.com
   # 應該解析到 192.168.0.10 或公網 IP
   ```

4. **驗證 Ingress**:
   ```bash
   kubectl get ingress -n grafana
   # 檢查 ADDRESS 字段

   curl -k https://grafana.detectviz.com
   # 應該返回 Grafana 登入頁面
   ```

5. **驗證 Keycloak SSO**:
   - 訪問: `https://grafana.detectviz.com`
   - 點擊 "Sign in with Keycloak"
   - 應該正常重定向並登入

---

## 📝 更新文檔

需要更新的檔案：

1. **app-deploy-checklist.md**:
   - 添加 Phase 6.6: "ArgoCD Keycloak SSO 整合"
   - 添加 Phase 6.7: "Grafana 域名遷移"

2. **VAULT_PATH_STRUCTURE.md**:
   - 添加 `secret/argocd/oauth/keycloak-client-secret`

3. **app-deploy-sop.md**:
   - 更新所有 Grafana URL 為 `grafana.detectviz.com`

4. **scripts/validate-post-deployment.sh**:
   - 更新 Ingress 檢查域名

---

## ⚠️ 風險與注意事項

### ArgoCD SSO 遷移風險

1. **備用管理員帳號**:
   - ⚠️ **必須保留** local admin 帳號 (`admin.enabled: true`)
   - 如果 Keycloak 故障，仍可使用 admin 帳號登入

2. **RBAC 配置錯誤**:
   - 可能導致用戶無法訪問資源
   - **建議**: 先在測試環境驗證 RBAC 策略

3. **Session 中斷**:
   - 修改 SSO 配置後，所有現有 session 會失效
   - 用戶需要重新登入

### Grafana 域名遷移風險

1. **DNS 傳播延遲**:
   - 如果使用公網 DNS，可能需要等待 TTL 過期
   - **建議**: 先使用內網 DNS 或 hosts 測試

2. **TLS 證書**:
   - Let's Encrypt 需要公網可訪問 (HTTP-01 challenge)
   - **建議**: 如果內網環境，使用 selfsigned ClusterIssuer

3. **OAuth Redirect 問題**:
   - 如果 Keycloak redirect URIs 配置錯誤，登入會失敗
   - **建議**: 過渡期保留兩個域名的 redirect URIs

4. **Grafana Alerting 通知 URL**:
   - 告警通知中的連結會包含 root_url
   - 遷移後需要驗證告警通知連結正確性

---

## 📊 實施時間表

| 階段 | 任務 | 預估時間 | 前置條件 |
|------|------|----------|----------|
| Phase A.1 | 在 Keycloak 創建 ArgoCD Client | 15 分鐘 | Keycloak 運行 |
| Phase A.2 | 配置 ArgoCD Dex Connector | 30 分鐘 | Vault secrets 準備 |
| Phase A.3 | 配置 ArgoCD RBAC | 20 分鐘 | - |
| Phase A.4 | 驗證 ArgoCD SSO | 15 分鐘 | - |
| Phase B.1 | 配置 DNS | 10 分鐘 | DNS 控制權 |
| Phase B.2 | 更新 Keycloak Client | 5 分鐘 | - |
| Phase B.3 | 更新 Grafana 配置 | 20 分鐘 | - |
| Phase B.4 | 創建 Grafana Ingress | 15 分鐘 | cert-manager 運行 |
| Phase B.5 | 部署與驗證 | 30 分鐘 | - |
| **總計** | | **~2.5 小時** | |

---

## 🔄 回滾計劃

### ArgoCD SSO 回滾

如果 Keycloak SSO 有問題：

1. **使用 local admin 登入**:
   ```bash
   argocd login argocd.detectviz.internal --username admin
   ```

2. **移除 Keycloak connector**:
   ```bash
   kubectl edit configmap argocd-cm -n argocd
   # 刪除 Keycloak connector 配置
   ```

3. **重啟 ArgoCD**:
   ```bash
   kubectl rollout restart deployment argocd-server argocd-dex-server -n argocd
   ```

### Grafana 域名回滾

如果新域名有問題：

1. **恢復舊配置**:
   ```bash
   git revert <commit-sha>
   git push
   argocd app sync grafana
   ```

2. **或手動修改**:
   ```bash
   kubectl edit configmap grafana -n grafana
   # 修改 GF_SERVER_DOMAIN 回 grafana.detectviz.internal

   kubectl rollout restart deployment grafana -n grafana
   ```

---

## 📚 參考資源

- [ArgoCD OIDC Configuration](https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/#existing-oidc-provider)
- [ArgoCD Dex Connectors](https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/keycloak/)
- [Grafana Generic OAuth](https://grafana.com/docs/grafana/latest/setup-grafana/configure-security/configure-authentication/generic-oauth/)
- [Keycloak OIDC Clients](https://www.keycloak.org/docs/latest/server_admin/#_oidc_clients)
- [Nginx Ingress Annotations](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/)
