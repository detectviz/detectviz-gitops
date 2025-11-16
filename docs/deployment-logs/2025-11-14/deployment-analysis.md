# DetectViz 基礎設施部署分析 (2025-11-14 13:05)

## 當前情況

### 背景部署任務
- Ansible playbook 正在重新部署 ArgoCD (從 "Apply ArgoCD install manifest" 任務開始)
- 原因: 之前的部署中 argocd-dex-server 部署超時
- 狀態: 正在執行中

### 之前已完成的修復

1. **IngressClass 權限問題** ✅
   - 已移動到 clusterResourceWhitelist
   - Commit: f82e0cd

2. **TopoLVM/Vault 資源權限** ✅
   - 已添加所有缺失的資源類型 (Certificate, Issuer, PriorityClass, CSIDriver, PodDisruptionBudget)
   - Commit: d225e09

3. **Volume Group 名稱修正** ✅
   - 從 data-vg → topolvm-vg
   - 檔案: argocd/apps/infrastructure/topolvm/overlays/values.yaml
   - Commit: 91cfbeb

4. **Vault StorageClass 修正** ✅
   - 從 detectviz-data → topolvm-provisioner
   - 檔案: argocd/apps/infrastructure/vault/overlays/values.yaml
   - Commit: 4114b77

5. **文件同步** ✅
   - deploy.md 已更新為 topolvm-vg
   - Commit: 4049c5f

## 待驗證問題

### Issue: Vault Pod 調度失敗 - "Insufficient topolvm.io/capacity"

**現象:**
- Vault pods (vault-0/1/2) 處於 Pending 狀態
- 錯誤訊息: "Insufficient topolvm.io/capacity"
- Pod 資源請求顯示: `topolvm.io/capacity: "1"` (1 byte)

**可能原因分析:**

1. **TopoLVM Mutating Webhook 問題**
   - Webhook 應該根據 PVC 請求自動注入正確的容量需求
   - 實際注入的是 "1" byte 而非預期的 45GB (6 PVCs: 3×10Gi + 3×5Gi)

2. **Scheduler 容量計算問題**
   - 節點標註顯示有 257GB 可用容量
   - 但 scheduler 認為容量不足

3. **PVC Binding Mode 問題**
   - StorageClass 使用 WaitForFirstConsumer binding mode
   - PVC 應該等到 Pod 調度後才綁定
   - 但 Pod 因容量不足無法調度,形成死鎖

**需要檢查的內容:**
1. TopoLVM mutating webhook 日誌
2. TopoLVM scheduler 日誌
3. TopoLVM controller 是否正確報告容量給節點
4. Vault Helm chart 是否有自定義資源請求覆寫

## 下一步行動

等待 Ansible 部署完成後:

1. 檢查 ArgoCD 應用同步狀態
2. 驗證 TopoLVM 所有組件 (controller, lvmd, node, scheduler) 都正常運行
3. 檢查 TopoLVM webhook 和 scheduler 日誌
4. 測試簡單的 PVC 創建是否成功
5. 解決 Vault pod 調度問題
6. 生成最終狀態報告
