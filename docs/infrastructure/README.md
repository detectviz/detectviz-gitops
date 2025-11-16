# DetectViz Infrastructure Documentation

本目錄包含 DetectViz 平台基礎設施的詳細文檔。

## 📁 目錄結構

### 04-ansible/
Ansible 自動化部署相關文檔

- **configuration/** - 配置和設定文檔
- **troubleshooting/** - 故障排除和修復文檔

### 05-argocd/
ArgoCD GitOps 平台相關文檔

- **deployment/** - 部署指南
  - quick-start.md - 快速開始指南
- **troubleshooting/** - 故障排除
  - argocd-config-fixes.md - ArgoCD 配置修復摘要
  - git-repository-setup.md - Git Repository SSH 認證設定與自動化
  - ingress-loadbalancer-fix.md - Ingress-Nginx LoadBalancer 配置修復

### 06-kubernetes/
Kubernetes 集群相關文檔

- **deployment/** - 部署文檔
  - vault-deployment.md - Vault HA 部署成功報告
- **monitoring/** - 監控相關
  - cluster-health-check.md - 集群健康檢查
- **troubleshooting/** - 故障排除
  - storage-topolvm-fixes.md - TopoLVM 調度與容量追蹤問題修復

## 🔗 相關文檔

- **項目根目錄**
  - [deploy.md](../../deploy.md) - 完整部署手冊
  - [deploy-app.md](../../deploy-app.md) - 應用部署指南
  - [README.md](../../README.md) - 項目總覽

- **應用指南**
  - [docs/app-guide/](../app-guide/) - 各應用的規格與最佳實踐

- **部署日誌**
  - [docs/deployment-logs/](../deployment-logs/) - 歷史部署記錄

## 🔧 快速鏈接

### 常見問題
- [ArgoCD 無法同步 Git Repository](05-argocd/troubleshooting/git-repository-setup.md)
- [Ingress LoadBalancer 無法分配 IP](05-argocd/troubleshooting/ingress-loadbalancer-fix.md)
- [TopoLVM Pods 調度失敗](06-kubernetes/troubleshooting/storage-topolvm-fixes.md)
- [Vault 部署和初始化](06-kubernetes/deployment/vault-deployment.md)

---

**文檔版本**: 1.0  
**最後更新**: 2025-11-14
