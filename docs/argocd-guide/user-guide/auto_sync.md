# 自動同步原則

當 Argo CD 偵測到 Git 中期望的資訊清單與叢集中的即時狀態之間存在差異時，它能夠自動同步應用程式
。自動同步的一個好處是，
CI/CD 管線不再需要直接存取 Argo CD API 伺服器來執行部署。
取而代之的是，管線會對 Git 儲存庫進行提交並推送，其中包含對
追蹤 Git 儲存庫中資訊清單的變更。

若要設定自動同步，請執行：
```bash
argocd app set <APPNAME> --sync-policy automated
```

或者，如果在建立應用程式資訊清單時，請指定一個具有 `automated` 原則的 syncPolicy。
```yaml
spec:
  syncPolicy:
    automated: {}
```
應用程式 CRD 現在也支援透過將 `spec.syncPolicy.automated.enabled` 旗標設定為 true 或 false 來明確地開啟或關閉自動同步。當 `enable` 欄位設定為 true 時，自動同步會啟用，而當設定為 false 時，即使已設定 `prune`、`self-heal` 和 `allowEmpty`，控制器也會略過自動同步。
```yaml
spec:
  syncPolicy:
    automated:
      enabled: true
```

> [!NOTE]
> 將 `spec.syncPolicy.automated.enabled` 旗標設定為 null 將被視為已啟用自動同步。當 `enabled` 欄位設定為 false 時，可以設定 `prune`、`selfHeal` 和 `allowEmpty` 等欄位，而無需啟用它們。

## 暫時切換由 ApplicationSets 管理的應用程式的自動同步

對於獨立的應用程式，切換自動同步是透過變更應用程式的 `spec.syncPolicy.automated` 欄位來執行的。但是，對於由 ApplicationSet 管理的應用程式，變更應用程式的 `spec.syncPolicy.automated` 欄位將沒有效果。
有關如何為由 ApplicationSets 管理的應用程式執行切換的更多詳細資訊，請參閱[此處](../operator-manual/applicationset/Controlling-Resource-Modification.md)。


## 自動刪除

預設情況下（並且作為一種安全機制），當 Argo CD 偵測到
資源在 Git 中不再被定義時，自動同步將不會刪除資源。若要刪除資源，可以隨時
執行手動同步（並勾選刪除選項）。刪除也可以設定為自動同步的一部分，方法是執行：

```bash
argocd app set <APPNAME> --auto-prune
```

或是在自動同步原則中將刪除選項設定為 true：

```yaml
spec:
  syncPolicy:
    automated:
      prune: true
```

## 使用 Allow-Empty 自動刪除 (v1.8)

預設情況下（並且作為一種安全機制），具有刪除功能的自動同步具有防止任何自動化/人為錯誤
在沒有目標資源時的保護。它防止應用程式具有空的資源。若要允許應用程式具有空的資源，請執行：

```bash
argocd app set <APPNAME> --allow-empty
```

或是在自動同步原則中將允許空選項設定為 true：

```yaml
spec:
  syncPolicy:
    automated:
      prune: true
      allowEmpty: true
```

## 自動自我修復
預設情況下，對即時叢集所做的變更不會觸發自動同步。若要在即時叢集的狀態偏離 Git 中定義的狀態時啟用自動同步，請執行：

```bash
argocd app set <APPNAME> --self-heal
```

或是在自動同步原則中將自我修復選項設定為 true：

```yaml
spec:
  syncPolicy:
    automated:
      selfHeal: true
```

> [!NOTE]
> 停用自我修復並不保證多來源應用程式中的即時叢集變更會持續存在。雖然其中一個資源的來源保持不變，但另一個來源的變更可能會觸發 `autosync`。若要處理這種情況，請考慮停用 `autosync`。

## 新修訂版本的自動重試重新整理

此功能允許使用者設定其應用程式在目前同步重試時，在新修訂版本上重新整理。若要在同步重試期間啟用自動重新整理，請執行：

```bash
argocd app set <APPNAME> --sync-retry-refresh
```

或是在同步原則中將 `retry.refresh` 選項設定為 `true`：

```yaml
spec:
  syncPolicy:
    retry:
      refresh: true
```

## 自動同步語意

* 只有當應用程式處於 OutOfSync 狀態時，才會執行自動同步。處於
  Synced 或錯誤狀態的應用程式將不會嘗試自動同步。
* 自動同步只會針對 commit SHA1 和
  應用程式參數的每個唯一組合嘗試一次同步。如果歷史記錄中最近一次成功的同步已
  針對相同的 commit-SHA 和參數執行，則不會嘗試第二次同步，除非 `selfHeal` 旗標設定為 true。
* 如果 `selfHeal` 旗標設定為 true，則會在自我修復逾時（預設為 5 秒）後再次嘗試同步，
此逾時由 `argocd-application-controller` 部署的 `--self-heal-timeout-seconds` 旗標控制。
* 如果先前針對相同的 commit-SHA
  和參數的同步嘗試失敗，則自動同步將不會重新嘗試同步。

* 無法對已啟用自動同步的應用程式執行回復。
* 自動同步間隔由 [`argocd-cm` ConfigMap 中的 `timeout.reconciliation` 值](../faq.md#how-often-does-argo-cd-check-for-changes-to-my-git-or-helm-repository)決定，預設為 `120s`，並加上 `60s` 的抖動，最長為 3 分鐘。
