# 新增外部 URL

您可以在 Argo CD 儀表板中新增額外的外部連結。例如，
連結到監控頁面或文件，而不僅僅是 ingress 主機或其他應用程式。

ArgoCD 會根據每個資源的註解，為資源產生可點擊的外部頁面連結。

範例：
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-svc
  annotations:
    link.argocd.argoproj.io/external-link: http://my-grafana.example.com/pre-generated-link
```
![外部連結](../assets/external-link.png)

在 ArgoCD 應用程式詳細資料頁面上，對應資源的外部連結圖示將會顯示。

![外部連結](../assets/external-link-1.png)
