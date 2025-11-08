# 同步時間窗

同步時間窗是可設定的時間範圍，在此期間同步將被阻止或允許。這些由 `kind`（可以是 `allow` 或 `deny`）、cron 格式的 `schedule` 和持續時間，以及 `applications`、`namespaces` 和 `clusters` 中的一個或多個來定義。如果指定了多個選項，預設情況下，啟用的選項將被 OR 運算。如果您想對選項進行 AND 運算，可以勾選 `Use AND operator` 選項。支援萬用字元。

## 同步時間窗與應用程式之間的關係

同步時間窗與應用程式資源之間的關係是多對多的。這意味著一個應用程式資源可能會受到多個同步時間窗的影響，而單一同步時間窗定義可能適用於多個應用程式資源。

同步時間窗與應用程式之間的關係是作為同步時間窗定義的一部分建立的。同步時間窗定義包含一個部分，定義了它所適用的應用程式資源。有三種機制可用於選擇同步時間窗適用的應用程式資源：

- 按應用程式資源的名稱
- 按應用程式資源將資源安裝到的叢集。這由 `Application.spec.destination.name` 和 `.server` 欄位指定
- 按應用程式資源將資源安裝到的命名空間。這由 `Application.spec.destination.namespace` 欄位指定。

所有三種機制都允許使用萬用字元。這些機制並非互斥，所有三種機制都可以在單一同步時間窗定義中使用。

當使用多個選擇機制時，它們實際上是 `ORed` 的，這意味著如果任何一個選擇器選擇了應用程式，那麼該應用程式就會受到同步時間窗的影響。

## 同步時間窗的效果

這些時間窗會影響手動和自動同步的執行，但允許手動同步的覆寫，這在您只關心防止自動同步或需要暫時覆寫時間窗以執行同步時非常有用。

時間窗的運作方式如下：

- 如果沒有與應用程式相符的時間窗，則允許所有同步。
- 如果有任何與應用程式相符的 `allow` 時間窗，則只有在有作用中的 `allow` 時間窗時才允許同步。
- 如果有任何與應用程式相符的 `deny` 時間窗，則在 `deny` 時間窗作用中時將拒絕所有同步。
- 如果同時有作用中的相符 `allow` 和作用中的相符 `deny`，則同步將被拒絕，因為 `deny` 時間窗會覆寫 `allow` 時間窗。

UI 和 CLI 都會顯示同步時間窗的狀態。UI 有一個面板，會根據狀態顯示不同的顏色。顏色如下。`紅色：同步被拒絕`，`橘色：允許手動` 和 `綠色：同步被允許`。

若要使用 CLI 顯示同步狀態：

```bash
argocd app get APP
```

這將傳回同步狀態和任何相符的時間窗。

```
Name:               guestbook
Project:            default
Server:             in-cluster
Namespace:          default
URL:                http://localhost:8080/applications/guestbook
Repo:               https://github.com/argoproj/argocd-example-apps.git
Target:
Path:               guestbook
SyncWindow:         Sync Denied
Assigned Windows:   deny:0 2 * * *:1h,allow:0 2 3 3 3:1h
Sync Policy:        Automated
Sync Status:        Synced to  (5c2d89b)
Health Status:      Healthy
```

可以使用 CLI 建立時間窗：

```bash
argocd proj windows add PROJECT \
    --kind allow \
    --schedule "0 22 * * *" \
    --duration 1h \
    --applications "*"
```

或者，它們可以直接在 `AppProject` 資訊清單中建立：
 
```yaml
apiVersion: argocd.argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: default
spec:
  syncWindows:
  - kind: allow
    schedule: '10 1 * * *'
    duration: 1h
    applications:
    - '*-prod'
    manualSync: true
  - kind: deny
    schedule: '0 22 * * *'
    timeZone: "Europe/Amsterdam"
    duration: 1h
    namespaces:
    - default
  - kind: allow
    schedule: '0 23 * * *'
    duration: 1h
    clusters:
    - in-cluster
    - cluster1
```

為了在同步被時間窗阻止時執行同步，您可以將時間窗設定為允許手動同步，方法是使用 CLI、UI 或直接在 `AppProject` 資訊清單中進行設定：

```bash
argocd proj windows enable-manual-sync PROJECT ID
```

若要停用

```bash
argocd proj windows disable-manual-sync PROJECT ID
```

可以使用 CLI 列出時間窗或在 UI 中檢視：

```bash
argocd proj windows list PROJECT
```

```bash
ID  STATUS    KIND   SCHEDULE    DURATION  APPLICATIONS  NAMESPACES  CLUSTERS  MANUALSYNC
0   Active    allow  * * * * *   1h        -             -           prod1     Disabled
1   Inactive  deny   * * * * 1   3h        -             default     -         Disabled
2   Inactive  allow  1 2 * * *   1h        prod-*        -           -         Enabled
3   Active    deny   * * * * *   1h        -             default     -         Disabled
```

時間窗的所有欄位都可以使用 CLI 或 UI 進行更新。`applications`、`namespaces` 和 `clusters` 欄位要求更新包含所有必要的值。例如，如果更新 `namespaces` 欄位且它已包含 default 和 kube-system，則新值必須在清單中包含這些值。

```bash
argocd proj windows update PROJECT ID --namespaces default,kube-system,prod1
```
