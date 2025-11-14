# DetectViz Deployment Logs

本目錄保存歷史部署記錄和狀態報告。

## 📁 目錄結構

### 2025-11-14/
2025年11月14日的部署記錄

- **ansible-reports/** - Ansible 部署相關報告
  - DEPLOYMENT_COMPLETE_FINAL.md - 最終部署完成報告
  - DEPLOYMENT_SUCCESS_SUMMARY.md - 部署成功摘要
  - CONFIGURATION_SYNC_STATUS.md - 配置同步狀態
  - 等等...

- **根目錄文件** - 部署狀態快照
  - deployment-status-20251114-2356.md - 2025-11-14 23:56 狀態檢查點
  - current-status-summary.md - 當前狀態摘要
  - final-deployment-report-20251114-2150.md - 最終部署報告
  - deployment-analysis.md - 部署分析

## 📋 日誌組織原則

### 文件命名
- 使用日期格式: YYYYMMDD 或 YYYYMMDD-HHMM
- 狀態報告: `*-status-*.md`
- 最終報告: `final-*-report-*.md`
- 分析文檔: `*-analysis.md`

### 歸檔策略
1. 按日期組織 (YYYY-MM-DD/)
2. 按來源分類 (ansible-reports/, argocd-reports/, etc.)
3. 保留完整的時間戳
4. 不修改原始內容

## 🔍 如何使用

### 查看特定日期的部署
```bash
ls docs/deployment-logs/2025-11-14/
```

### 查找特定類型的報告
```bash
find docs/deployment-logs -name "*status*.md"
find docs/deployment-logs -name "*final*.md"
```

### 查看最新狀態
查看最新日期目錄中的文件

---

**歸檔開始日期**: 2025-11-14  
**維護**: 自動歸檔過時的部署文檔
