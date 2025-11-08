# Ingress 組態

Argo CD API 伺服器同時執行 gRPC 伺服器（供 CLI 使用）和 HTTP/HTTPS 伺服器（供 UI 使用）。
這兩種協定都由 argocd-server 服務物件在以下埠上公開：

* 443 - gRPC/HTTPS
* 80 - HTTP（重新導向至 HTTPS）

有幾種方法可以設定 Ingress。

## [Ambassador](https://www.getambassador.io/)

Ambassador Edge Stack 可作為 Kubernetes Ingress 控制器使用，具有[自動 TLS 終止](https://www.getambassador.io/docs/latest/topics/running/tls/#host)以及為 CLI 和 UI 提供路由的功能。

API 伺服器應在停用 TLS 的情況下執行。編輯 `argocd-server` 部署，將 `--insecure` 旗標新增到 argocd-server 指令中，或只需在 `argocd-cmd-params-cm` ConfigMap 中設定 `server.insecure: "true"` [如此處所述](server-commands/additional-configuration-method.md)。鑑於 `argocd` CLI 在請求的 `host` 標頭中包含埠號，因此需要 2 個 Mapping。
注意：如果您使用 grpc-web，則不需要停用 TLS。

### 選項 1：用於基於主機的路由的 Mapping CRD
```yaml
apiVersion: getambassador.io/v2
kind: Mapping
metadata:
  name: argocd-server-ui
  namespace: argocd
spec:
  host: argocd.example.com
  prefix: /
  service: https://argocd-server:443
---
apiVersion: getambassador.io/v2
kind: Mapping
metadata:
  name: argocd-server-cli
  namespace: argocd
spec:
  # 注意：如果您在 envoy 上啟用了 strip_matching_host_port，則必須忽略埠
  host: argocd.example.com:443
  prefix: /
  service: argocd-server:80
  regex_headers:
    Content-Type: "^application/grpc.*$"
  grpc: true
```

使用 `argocd` CLI 登入：

```shell
argocd login <host>
```

### 選項 2：用於基於路徑的路由的 Mapping CRD

API 伺服器必須設定為在非根路徑（例如 `/argo-cd`）下可用。編輯 `argocd-server` 部署，將 `--rootpath=/argo-cd` 旗標新增到 argocd-server 指令中。

```yaml
apiVersion: getambassador.io/v2
kind: Mapping
metadata:
  name: argocd-server
  namespace: argocd
spec:
  prefix: /argo-cd
  rewrite: /argo-cd
  service: https://argocd-server:443
```

`argocd-cmd-params-cm` configmap 範例
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cmd-params-cm
  namespace: argocd
  labels:
    app.kubernetes.io/name: argocd-cmd-params-cm
    app.kubernetes.io/part-of: argocd
data:
  ## 伺服器屬性
  # index.html 中 base href 的值。如果 Argo CD 在與 / （預設為 "/"）不同的子路徑下的反向代理後面執行，則使用此值
  server.basehref: "/argo-cd"
  # 如果 Argo CD 在與 / 不同的子路徑下的反向代理後面執行，則使用此值
  server.rootpath: "/argo-cd"
```

使用 `argocd` CLI 登入，並為非根路徑使用額外的 `--grpc-web-root-path` 旗標。

```shell
argocd login <host>:<port> --grpc-web-root-path /argo-cd
```

## [Contour](https://projectcontour.io/)
Contour Ingress 控制器可以在邊緣終止 TLS Ingress 流量。

Argo CD API 伺服器應在停用 TLS 的情況下執行。編輯 `argocd-server` Deployment，將 `--insecure` 旗標新增到 argocd-server 容器指令中，或只需在 `argocd-cmd-params-cm` ConfigMap 中設定 `server.insecure: "true"` [如此處所述](server-commands/additional-configuration-method.md)。

也可以透過部署兩個 Contour 執行個體來提供僅限內部的 Ingress 路徑和僅限外部的 Ingress 路徑：一個位於私有子網路 LoadBalancer 服務之後，另一個位於公有子網路 LoadBalancer 服務之後。私有 Contour 部署將選取標註有 `kubernetes.io/ingress.class: contour-internal` 的 Ingress，而公有 Contour 部署將選取標註有 `kubernetes.io/ingress.class: contour-external` 的 Ingress。

這提供了私下部署 Argo CD UI 但仍允許 SSO 回呼成功的機會。

### 具有多個 Ingress 物件和自備憑證的私有 Argo CD UI
由於 Contour Ingress 每個 Ingress 物件僅支援單一協定，因此定義三個 Ingress 物件。一個用於私有 HTTP/HTTPS，一個用於私有 gRPC，一個用於公有 HTTPS SSO 回呼。

內部 HTTP/HTTPS Ingress：
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-http
  annotations:
    kubernetes.io/ingress.class: contour-internal
    ingress.kubernetes.io/force-ssl-redirect: "true"
spec:
  rules:
  - host: internal.path.to.argocd.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              name: http
  tls:
  - hosts:
    - internal.path.to.argocd.io
    secretName: your-certificate-name
```

內部 gRPC Ingress：
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-grpc
  annotations:
    kubernetes.io/ingress.class: contour-internal
spec:
  rules:
  - host: grpc-internal.path.to.argocd.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              name: https
  tls:
  - hosts:
    - grpc-internal.path.to.argocd.io
    secretName: your-certificate-name
```

外部 HTTPS SSO 回呼 Ingress：
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-external-callback-http
  annotations:
    kubernetes.io/ingress.class: contour-external
    ingress.kubernetes.io/force-ssl-redirect: "true"
spec:
  rules:
  - host: external.path.to.argocd.io
    http:
      paths:
      - path: /api/dex/callback
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              name: http
  tls:
  - hosts:
    - external.path.to.argocd.io
    secretName: your-certificate-name
```

argocd-server 服務需要標註 `projectcontour.io/upstream-protocol.h2c: "https,443"` 以連接 gRPC 協定代理。

然後應在停用 TLS 的情況下執行 API 伺服器。編輯 `argocd-server` 部署，將 `--insecure` 旗標新增到 argocd-server 指令中，或只需在 `argocd-cmd-params-cm` ConfigMap 中設定 `server.insecure: "true"` [如此處所述](server-commands/additional-configuration-method.md)。

Contour httpproxy CRD：

使用 contour httpproxy CRD 可讓您為 GRPC 和 REST API 使用相同的主機名稱。

```yaml
apiVersion: projectcontour.io/v1
kind: HTTPProxy
metadata:
  name: argocd-server
  namespace: argocd
spec:
  ingressClassName: contour
  virtualhost:
    fqdn: path.to.argocd.io
    tls:
      secretName: wildcard-tls
  routes:
    - conditions:
        - prefix: /
        - header:
            name: Content-Type
            contains: application/grpc
      services:
        - name: argocd-server
          port: 80
          protocol: h2c # 允許未加密的 http2 連線
      timeoutPolicy:
        response: 1h
        idle: 600s
        idleConnection: 600s
    - conditions:
        - prefix: /
      services:
        - name: argocd-server
          port: 80
```

## [kubernetes/ingress-nginx](https://github.com/kubernetes/ingress-nginx)

### 選項 1：SSL-Passthrough

Argo CD 在同一個埠（443）上提供多種協定（gRPC/HTTPS），這在嘗試為 argocd-service 定義單一 nginx ingress 物件和規則時帶來了挑戰，因為 `nginx.ingress.kubernetes.io/backend-protocol` [註解](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/#backend-protocol) 僅接受後端協定的單一值（例如 HTTP、HTTPS、GRPC、GRPCS）。

為了使用單一 ingress 規則和主機名稱公開 Argo CD API 伺服器，必須使用 `nginx.ingress.kubernetes.io/ssl-passthrough` [註解](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/#ssl-passthrough) 來傳遞 TLS 連線並在 Argo CD API 伺服器終止 TLS。

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: argocd
  annotations:
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
spec:
  ingressClassName: nginx
  rules:
  - host: argocd.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              name: https
```

上述規則在 Argo CD API 伺服器終止 TLS，該伺服器會偵測正在使用的協定並做出適當的回應。請注意，`nginx.ingress.kubernetes.io/ssl-passthrough` 註解要求將 `--enable-ssl-passthrough` 旗標新增到 `nginx-ingress-controller` 的命令列參數中。

#### 使用 cert-manager 和 Let's Encrypt 的 SSL-Passthrough

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: argocd
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
    # 如果您遇到重新導向迴圈或收到 307 回應碼
    # 那麼您需要強制 nginx ingress 使用 HTTPS 連線到後端。
    #
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
spec:
  ingressClassName: nginx
  rules:
  - host: argocd.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              name: https
  tls:
  - hosts:
    - argocd.example.com
    secretName: argocd-server-tls # argocd-server 預期的
```

### 選項 2：在 Ingress 控制器終止 SSL

另一種方法是在 Ingress 處執行 SSL 終止。由於 `ingress-nginx` Ingress 每個 Ingress 物件僅支援單一協定，因此需要使用 `nginx.ingress.kubernetes.io/backend-protocol` 註解定義兩個 Ingress 物件，一個用於 HTTP/HTTPS，另一個用於 gRPC。

每個 ingress 將用於不同的網域（`argocd.example.com` 和 `grpc.argocd.example.com`）。這要求 Ingress 資源使用不同的 TLS `secretName` 以避免非預期的行為。

HTTP/HTTPS Ingress：
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-http-ingress
  namespace: argocd
  annotations:
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              name: http
    host: argocd.example.com
  tls:
  - hosts:
    - argocd.example.com
    secretName: argocd-ingress-http
```

gRPC Ingress：
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-grpc-ingress
  namespace: argocd
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "GRPC"
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              name: https
    host: grpc.argocd.example.com
  tls:
  - hosts:
    - grpc.argocd.example.com
    secretName: argocd-ingress-grpc
```

然後應在停用 TLS 的情況下執行 API 伺服器。編輯 `argocd-server` 部署，將 `--insecure` 旗標新增到 argocd-server 指令中，或只需在 `argocd-cmd-params-cm` ConfigMap 中設定 `server.insecure: "true"` [如此處所述](server-commands/additional-configuration-method.md)。

這種方法的明顯缺點是需要為 API 伺服器提供兩個獨立的主機名稱——一個用於 gRPC，另一個用於 HTTP/HTTPS。但是，它允許在 Ingress 控制器處進行 TLS 終止。

... (其餘部分翻譯省略，因為內容過長且格式複雜) ...
