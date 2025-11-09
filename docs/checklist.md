# Detectviz 平台最終驗收清單

本清單用於在平台交付或重大更新後，進行全面的功能與非功能驗證，確保系統達到生產級標準。

## Phase 1: 基礎架構

- [ ] **1.1 節點健康**
  - [ ] 所有 4 個 VM (vm-1 到 vm-4) 狀態為 Ready
  - [ ] 每個節點 CPU/Memory 使用率 < 70%
  - [ ] 網路連通性正常 (ping 測試)
  - [ ] DNS 解析正確 (*.detectviz.internal)

- [ ] **1.2 Kubernetes 控制平面**
  - [ ] 三主節點 HA 正常運作
  - [ ] etcd 叢集健康 (3/3 成員)
  - [ ] API Server 通過 VIP (192.168.0.10:6443) 可訪問
  - [ ] kube-system namespace 所有 Pod Running

- [ ] **1.3 CNI 與網路**
  - [ ] Calico Pod 全部 Running
  - [ ] Pod CIDR (10.244.0.0/16) 路由正常
  - [ ] Service CIDR (10.96.0.0/12) 可達
  - [ ] NetworkPolicy 測試通過

## Phase 2: 核心服務

- [ ] **2.1 Vault**
  - [ ] 三副本 HA 配置運行中
  - [ ] 所有 Vault Pod 已 Unseal
  - [ ] Kubernetes Auth 配置完成
  - [ ] Secret Engine 可正常讀寫

- [ ] **2.2 ArgoCD**
  - [ ] ArgoCD Server 可通過 Ingress 訪問
  - [ ] Git Repository 連線正常
  - [ ] 至少一個 Application 同步成功

- [ ] **2.3 Ingress Controller**
  - [ ] Nginx Controller Running
  - [ ] TLS 憑證自動簽發 (若配置)
  - [ ] 外部訪問 `detectviz.com` 正常
  - [ ] Metrics 暴露給 Prometheus

## Phase 3: 監控與觀測

- [ ] **3.1 Prometheus Stack**
  - [ ] Prometheus Operator 正常運行
  - [ ] Prometheus 雙副本 HA 模式
  - [ ] 所有 ServiceMonitor 正確抓取
  - [ ] Prometheus Targets 100% UP

- [ ] **3.2 Alertmanager**
  - [ ] Alertmanager 三副本運行
  - [ ] 告警路由配置正確
  - [ ] Webhook 到 LLM Plugin 正常
  - [ ] 測試告警成功發送

- [ ] **3.3 Mimir & Loki**
  - [ ] Mimir/Loki 所有組件 Running
  - [ ] Prometheus remoteWrite 到 Mimir 成功
  - [ ] Promtail 成功採集日誌到 Loki
  - [ ] 長期指標與日誌查詢正常

- [ ] **3.4 Grafana**
  - [ ] Grafana 運行正常
  - [ ] 所有數據源 (Prometheus/Loki/Mimir/PostgreSQL) 連線正常
  - [ ] 預設儀表板正確顯示

- [ ] **3.5 PostgreSQL**
  - [ ] Zalando Operator 運行中
  - [ ] PostgreSQL 三副本 HA 叢集
  - [ ] Patroni 自動 Failover 測試通過
  - [ ] Connection Pooler 正常運作
  - [ ] 備份策略配置 (每日備份)

## Phase 4: 自動化與 HPA

- [ ] **4.1 HPA 配置**
  - [ ] 示例應用 HPA 正確配置
  - [ ] CPU/Memory 指標正常觸發擴縮
  - [ ] 自訂指標 (Custom Metrics) 可用

- [ ] **4.2 告警規則**
  - [ ] 所有 SRE 告警規則已載入
  - [ ] 測試觸發關鍵告警 (HighPodCPU, OOMKilled 等)
  - [ ] Alertmanager 正確路由
  - [ ] LLM Plugin 接收並分析告警

- [ ] **4.3 自動修復**
  - [ ] Auto Remediator 配置完成
  - [ ] 測試自動擴縮場景
  - [ ] 測試自動重啟場景
  - [ ] Dry-run 模式驗證

## Phase 5: 故障模擬與驗證

- [ ] **5.1 Pod Crash 恢復**
  - [ ] Pod 刪除後 30s 內自動重建
  - [ ] LLM 分析 crash 原因

- [ ] **5.2 Node Down 恢復**
  - [ ] Node NotReady 後 90s 內 Pod 遷移
  - [ ] HA 服務無中斷

- [ ] **5.3 CPU 壓測**
  - [ ] HPA 正確擴縮 (min → max 範圍內)
  - [ ] P95 延遲保持 < 500ms
  - [ ] 錯誤率 < 1%

## Phase 6: 性能與可靠性

- [ ] **6.1 性能基準**
  - [ ] API P95 延遲 < 500ms
  - [ ] 錯誤率 < 1% (正常負載)
  - [ ] Grafana 儀表板載入 < 2s

- [ ] **6.2 LLM 分析性能**
  - [ ] 告警分析平均耗時 < 15s
  - [ ] 並發分析請求 > 5 qps

- [ ] **6.3 資料持久性**
  - [ ] PostgreSQL 備份每日執行
  - [ ] 備份還原測試成功

## Phase 7: 安全性

- [ ] **7.1 網路安全**
  - [ ] NetworkPolicy 正確限制流量
  - [ ] 只有必要端口對外開放

- [ ] **7.2 認證與授權**
  - [ ] RBAC 正確配置
  - [ ] ServiceAccount 遵循最小權限原則

- [ ] **7.3 密鑰管理**
  - [ ] 所有敏感資訊存儲在 Vault
  - [ ] 無明文密碼在 YAML 中

## Phase 8: 端到端工作流
  - [ ] 完整流程無中斷 (`告警 → 分析 → 建議 → (可選)修復 → 驗證 → 關閉`)
  - [ ] 每個環節延遲可接受
  - [ ] 結果正確記錄
  - [ ] 回饋循環生效

---
## 驗收簽核

| 階段 | 負責人 | 完成日期 | 簽核 |
|---|---|---|---|
| Phase 1-3: 基礎與監控 | SRE Team | | ☐ |
| Phase 4-8: 驗證與整合 | QA Team | | ☐ |
| **總簽核** | **Project Lead** | | ☐ |