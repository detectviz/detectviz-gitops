# APP Structure

參考 [argo-guide](/docs/argocd-guidehow-to-structure-your-argo-cd-repositories-using-application-sets.md) 來編輯設定檔，唯一差異是在 apps 資料夾下，多一層以 `namespace` 分類，再以 `service-name` 分類。

```bash
${namespace}/${service-name}
├── base/
│   ├── deployment.yaml
│   ├── kustomization.yaml
│   └── service.yaml
└── overlays/
    ├── deployment.yaml
    ├── kustomization.yaml
    ├── replicas.yaml
    ├── settings.yaml
    └── version.yaml
```