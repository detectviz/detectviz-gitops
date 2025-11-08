# Domain Setup Guide – detectviz.com

本文件說明如何從 GoDaddy 註冊網域後，完成：
1. DNS 設定
2. GitHub Pages 綁定 blog.detectviz.com
3. Grafana 公網展示 grafana.detectviz.com

---

## 1. GoDaddy DNS 設定

### 1.1 登入 GoDaddy
- 前往 [https://www.godaddy.com/](https://www.godaddy.com/)
- 進入 **My Products → detectviz.com → DNS → Manage DNS**

### 1.2 新增 DNS 記錄

| 類型 | 名稱 | 值 / 目的地 | 說明 |
|------|------|--------------|------|
| `CNAME` | `blog` | `username.github.io` | 用於 GitHub Pages 綁定（將 username 改成你的 GitHub 帳號或組織） |
| `A` | `grafana` | `<你的伺服器外部 IP>` | 指向 Grafana 反向代理或 Ingress 外部 IP |
| *(可選)* `A` | `@` | `<同上或 landing server IP>` | detectviz.com 主域入口，可作 landing page 或反向代理入口 |

> 變更後等待 5–30 分鐘生效，可用以下命令驗證：
> ```bash
> nslookup blog.detectviz.com
> nslookup grafana.detectviz.com
> ```

---

## 2. GitHub Pages 綁定 blog.detectviz.com

### 2.1 建立 GitHub Repo
1. 在 GitHub 建立新倉庫，例如 `detectviz-blog`
2. 放置文件結構：
   ```
   docs/
   ├── index.md
   ├── architecture-overview.md
   ├── installation-guide.md
   └── images/
   ```

### 2.2 啟用 GitHub Pages
1. 前往 **Settings → Pages**
2. Source: `Deploy from branch`
3. Branch: `main`，資料夾選擇 `/docs`
4. 在 **Custom domain** 欄位填入：
   ```
   blog.detectviz.com
   ```
   GitHub 會自動簽發憑證並顯示 HTTPS 啟用狀態。

### 2.3 自動部署（可選）
在 `.github/workflows/deploy.yml` 加入：

```yaml
name: Deploy Docs
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-python@v4
        with:
          python-version: '3.11'
      - run: pip install mkdocs-material
      - run: mkdocs gh-deploy --force
```

完成後，`https://blog.detectviz.com` 會自動更新文件內容。

---

## 3. Grafana 公網展示設定

### 3.1 前置條件
確保 Grafana 已正常運行於 Kubernetes 或 Proxmox VM：
- Grafana Service 可用 (`kubectl get svc -n monitoring`)
- Ingress Controller（nginx / traefik）已部署
- cert-manager 可成功簽發 Let's Encrypt 憑證

### 3.2 Ingress 範例

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana
  namespace: monitoring
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx
  tls:
  - hosts:
      - grafana.detectviz.com
    secretName: grafana-tls
  rules:
  - host: grafana.detectviz.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: prometheus-grafana
            port:
              number: 80
```

### 3.3 DNS 指向與驗證

在 GoDaddy 中設定：
```
A   grafana.detectviz.com   → <Ingress 外部 IP>
```

等待 DNS 傳播完成後，測試：
```bash
curl -I https://grafana.detectviz.com
```

若出現：
```
HTTP/2 200
```
表示部署成功。

---

## 4. 安全與建議

| 項目 | 建議 |
|------|------|
| Grafana 公開展示 | 啟用匿名只讀模式，關閉管理帳號外部登入。 |
| Blog 與 Grafana 隔離 | Blog 在 GitHub Pages（靜態內容），Grafana 在內部叢集（動態監控）。 |
| 憑證管理 | 建議使用 cert-manager 自動簽發，GitHub Pages 憑證由 GitHub 自行維護。 |
| DNS 維護 | 建議後續移管至 Cloudflare，支援自動 SSL proxy 與動態更新。 |

---

## 5. 架構總覽

```text
GoDaddy DNS
│
├── blog.detectviz.com → GitHub Pages (靜態文件)
│
└── grafana.detectviz.com → Kubernetes Ingress / Grafana Service (動態監控)
```

---

**完成以上設定後：**
- 你的文件站點可在 `https://blog.detectviz.com` 存取。
- Grafana 儀表板可在 `https://grafana.detectviz.com` 安全展示。