# 同步階段與波次

同步階段與鉤子 (hooks) 定義了資源的套用時機，例如在主要同步操作之前或之後。這使得可以定義作業 (jobs) 或任何其他資源，以任何特定順序執行或套用。

Argo CD 具有以下鉤子類型：

| 鉤子 | 說明 |
|------|-------------|
| `PreSync` | 在套用資訊清單之前執行。 |
| `Sync`  | 在所有 `PreSync` 鉤子完成並成功後，與套用資訊清單同時執行。 |
| `Skip` | 指示 Argo CD 略過資訊清單的套用。 |
| `PostSync` | 在所有 `Sync` 鉤子完成並成功、應用程式成功，且所有資源處於 `Healthy` 狀態後執行。 |
| `SyncFail` | 在同步操作失敗時執行。 |
| `PostDelete` | 在刪除所有應用程式資源後執行。_自 v2.10 起可用。_ |

將 `argocd.argoproj.io/hook` 註解新增至資源，會將其指派給特定階段。在同步操作期間，Argo CD 將在部署的適當階段套用該資源。鉤子可以是任何類型的 Kubernetes 資源種類，但通常是 Pod、Job 或 Argo Workflows。可以將多個鉤子指定為以逗號分隔的清單。

## 階段如何運作？

Argo CD 在同步操作期間會尊重指派給不同階段的資源，Argo CD 將執行以下操作。

套用所有標記為 PreSync 鉤子的資源。如果其中任何一個失敗，整個同步過程將停止並標記為失敗
套用所有標記為 Sync 鉤子的資源。如果其中任何一個失敗，整個同步過程將標記為失敗。標記為 SyncFail 的鉤子也會執行
套用所有標記為 PostSync 鉤子的資源。如果其中任何一個失敗，整個同步過程將標記為失敗。
標記為 Skip 的鉤子將不會被套用。

以下是同步過程的圖形化概覽：

![階段](how_phases_work.png)

您可以在各種情況下使用這種簡單的生命週期方法。例如，您可以將必要的檢查作為 PreSync 鉤子執行。如果失敗，整個同步操作將停止，從而阻止部署進行。同樣地，您可以將煙霧測試作為 PostSync 鉤子執行。如果成功，您就知道您的應用程式已通過驗證。如果失敗，整個部署將標記為失敗，Argo CD 屆時可以通知您採取進一步行動。

SyncFail 階段的鉤子可用於清理動作和其他內務管理任務。請注意，如果它們本身失敗，Argo CD 不會做任何特別的事情（除了將整個操作標記為失敗）。

請注意，在選擇性同步操作期間不會執行鉤子。

## 鉤子生命週期與清理

Argo CD 提供了幾種方法來清理鉤子並決定先前執行的歷史記錄將保留多少。
在最基本的情況下，您可以使用 `argocd.argoproj.io/hook-delete-policy` 來決定何時刪除鉤子。
這可以採用以下值：

| 策略 | 說明 |
|--------|-------------|
| `HookSucceeded` | 鉤子資源在鉤子成功後刪除（例如 Job/Workflow 成功完成）。 |
| `HookFailed` | 鉤子資源在鉤子失敗後刪除。 |
| `BeforeHookCreation` | 在建立新鉤子資源之前刪除任何現有的鉤子資源（自 v1.3 起）。它旨在與 `/metadata/name` 一起使用。 |


## 同步波次如何運作？

Argo CD 也提供了一種改變資源同步順序的替代方法。這些是同步波次。它們由 `argocd.argoproj.io/sync-wave` 註解定義。該值是一個整數，定義了順序（ArgoCD 將從最小的數字開始部署，並以最大的數字結束）。

鉤子和資源預設分配給波次 0。波次可以是負數，因此您可以建立一個在所有其他資源之前執行的波次。

當同步操作發生時，Argo CD 將：
根據其波次（從低到高）對所有資源進行排序
根據產生的順序套用資源

目前每個同步波次之間都有一個延遲，以便讓其他控制器有機會對剛才套用的規格變更做出反應。這也防止 Argo CD 過快地評估資源健康狀況（針對過時的物件），導致鉤子過早觸發。目前每個同步波次之間的延遲為 2 秒，可以透過環境變數 `ARGOCD_SYNC_WAVE_DELAY` 進行設定。

## 結合同步波次與鉤子

雖然您可以單獨使用同步波次，但為了獲得最大的靈活性，您可以將它們與鉤子結合使用。這樣，您可以使用同步階段進行粗略的排序，並使用同步波次來定義單一階段內資源的確切順序。

![波次](how_waves_work.png)

當 Argo CD 開始同步時，它會按照以下優先順序對資源進行排序：

階段
它們所在的波次（較小的值優先）
按種類（例如，命名空間優先，然後是其他 Kubernetes 資源，其次是自訂資源）
按名稱

一旦定義了順序：

首先，Argo CD 確定要套用的第一個波次的編號。這是任何資源處於不同步或不健康狀態的第一個編號。
它會套用該波次中的資源。
它會重複此過程，直到所有階段和波次都處於同步且健康的狀態。

因為應用程式的第一個波次中可能有不健康的資源，所以應用程式可能永遠無法達到健康的狀態。

## 我該如何設定階段？

前同步和後同步只能包含鉤子。套用鉤子註解：

```yaml
metadata:
  annotations:
    argocd.argoproj.io/hook: PreSync
```

[閱讀更多關於鉤子的資訊](resource_hooks.md)。

## 我該如何設定波次？

使用以下註解指定波次：

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "5"
```

鉤子和資源預設分配給波次零。波次可以是負數，因此您可以建立一個在所有其他資源之前執行的波次。

## 範例

### 同步完成時向 Slack 傳送訊息

以下範例使用 Slack API 在同步完成時傳送 Slack 訊息：

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  generateName: app-slack-notification-
  annotations:
    argocd.argoproj.io/hook: PostSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
spec:
  template:
    spec:
      containers:
        - name: slack-notification
          image: curlimages/curl
          command:
            - curl
            - '-X'
            - POST
            - '--data-urlencode'
            - >-
              payload={"channel": "#somechannel", "username": "hello", "text":
              "App Sync succeeded", "icon_emoji": ":ghost:"}
            - 'https://hooks.slack.com/services/...'
      restartPolicy: Never
  backoffLimit: 2
```

以下範例在主要同步操作之前（也在波次 -1 中）執行資料庫遷移指令：
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migrate
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
    argocd.argoproj.io/sync-wave: '-1'
spec:
  ttlSecondsAfterFinished: 360
  template:
    spec:
      containers:
        - name: postgresql-client
          image: 'my-postgres-data:11.5'
          imagePullPolicy: Always
          env:
            - name: PGPASSWORD
              value: admin
            - name: POSTGRES_HOST
              value: my_postgresql_db
          command:
            - psql
            - '-h=my_postgresql_db'
            - '-U postgres'
            - '-f preload.sql'
      restartPolicy: Never
  backoffLimit: 1
```

### 解決 ArgoCD 同步失敗的問題

使用 ArgoCD 2.x 升級 ingress-nginx 控制器（由 helm 管理）有時會失敗，導致：

.|.
-|-
OPERATION|Sync
PHASE|Running
MESSAGE|waiting for completion of hook batch/Job/ingress-nginx-admission-create

.|.
-|-
KIND     |batch/v1/Job
NAMESPACE|ingress-nginx
NAME     |ingress-nginx-admission-create
STATUS   |Running
HOOK     |PreSync
MESSAGE  |Pending deletion

為了解決這個問題，helm 使用者可以新增：

```yaml
ingress-nginx:
  controller:
    admissionWebhooks:
      annotations:
        argocd.argoproj.io/hook: Skip
```

這會導致同步成功。
