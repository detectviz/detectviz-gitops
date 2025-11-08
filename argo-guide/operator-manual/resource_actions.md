# 資源動作

## 總覽
Argo CD 允許操作員定義使用者可以對特定資源類型執行的自訂動作。這在內部用於為 `DaemonSet` 提供 `restart` 或為 Argo Rollout 提供 `retry` 等動作。

操作員可以以 Lua 腳本的形式將動作新增至自訂資源，並擴展這些功能。

## 內建動作

以下是內建於 Argo CD 的動作。每個動作名稱都會連結到其 Lua 腳本定義：

{!docs/operator-manual/resource_actions_builtin.md!}

有關如何控制對這些動作的存取的資訊，請參閱 [RBAC 文件](rbac.md#the-action-action)。

## 自訂資源動作

Argo CD 支援以 [Lua](https://www.lua.org/) 撰寫的自訂資源動作。如果您遇到以下情況，這會很有用：

* 您有一個 Argo CD 未提供任何內建動作的自訂資源。
* 您有一個常執行的手動任務，如果由使用者透過 `kubectl` 執行，可能會容易出錯。

資源動作作用於單一物件。

您可以在 `argocd-cm` ConfigMap 中定義您自己的自訂資源動作。

### 自訂資源動作類型

#### 修改來源資源的動作

此動作會修改並傳回來源資源。
這種動作是 2.8 版之前唯一可用的動作，目前仍然支援。

#### 產生新資源或已修改資源清單的動作

**2.8 版中引入的 alpha 功能。**

此動作會傳回受影響資源的清單，每個受影響的資源都有一個 K8S 資源和要執行的操作。
目前支援的操作為 "create" 和 "patch"，"patch" 僅支援來源資源。
可以建立新資源，方法是在傳回的清單中為每個此類資源指定一個 "create" 操作。
如有需要，傳回的資源之一可以是已修改的來源物件，並帶有 "patch" 操作。
請參閱下面的定義範例。

### 在 `argocd-cm` ConfigMap 中定義自訂資源動作

自訂資源動作可以在 `argocd-cm` 的 `resource.customizations.actions.<group_kind>` 欄位中定義。以下範例展示了 `CronJob` 資源的一組自訂動作，每個此類動作都會傳回已修改的 CronJob。
自訂金鑰的格式為 `resource.customizations.actions.<apiGroup_Kind>`。

```yaml
resource.customizations.actions.batch_CronJob: |
  discovery.lua: |
    actions = {}
    actions["suspend"] = {["disabled"] = true}
    actions["resume"] = {["disabled"] = true}
  
    local suspend = false
    if obj.spec.suspend ~= nil then
        suspend = obj.spec.suspend
    end
    if suspend then
        actions["resume"]["disabled"] = false
    else
        actions["suspend"]["disabled"] = false
    end
    return actions
  definitions:
  - name: suspend
    action.lua: |
      obj.spec.suspend = true
      return obj
  - name: resume
    action.lua: |
      if obj.spec.suspend ~= nil and obj.spec.suspend then
          obj.spec.suspend = false
      end
      return obj
```

`discovery.lua` 腳本必須傳回一個表格，其中金鑰名稱代表動作名稱。您可以選擇性地包含邏輯，以根據目前的物件狀態啟用或停用某些動作。

每個動作名稱都必須在 `definitions` 清單中表示，並附有 `action.lua` 腳本以控制資源修改。`obj` 是一個包含資源的全域變數。每個動作腳本都會傳回一個可選修改版本的資源。在此範例中，我們只是將 `.spec.suspend` 設定為 `true` 或 `false`。

預設情況下，定義資源動作自訂將會覆寫此資源種類的任何內建動作。自 Argo CD 2.13.0 版起，如果您想保留內建動作，可以將 `mergeBuiltinActions` 金鑰設定為 `true`。您的自訂動作將優先於內建動作。
```yaml        
resource.customizations.actions.argoproj.io_Rollout: |
  mergeBuiltinActions: true
  discovery.lua: |
    actions = {}
    actions["do-things"] = {}
    return actions
  definitions:
  - name: do-things
    action.lua: |
      return obj		
```

#### 使用自訂動作建立新資源

> [!IMPORTANT]
> 透過 Argo CD UI 建立資源是刻意、策略性地背離 GitOps 原則。我們建議您謹慎使用此功能，且僅用於不屬於應用程式所需狀態一部分的資源。

叫用動作的資源將被稱為 `來源資源`。
新資源以及因此隱含建立的所有資源，都必須在 AppProject 層級獲得許可，否則建立將會失敗。

##### 使用自訂動作建立來源資源的子資源

如果新資源代表來源資源的 k8s 子資源，則必須在新資源上設定來源資源的 ownerReference。
以下是一個 Lua 程式碼片段範例，它負責建構一個作為來源 CronJob 資源子資源的 Job 資源 - `obj` 是一個全域變數，包含來源資源：

```lua
-- ...
ownerRef = {}
ownerRef.apiVersion = obj.apiVersion
ownerRef.kind = obj.kind
ownerRef.name = obj.metadata.name
ownerRef.uid = obj.metadata.uid
job = {}
job.metadata = {}
job.metadata.ownerReferences = {}
job.metadata.ownerReferences[1] = ownerRef
-- ...
```

##### 使用自訂動作建立獨立的子資源

如果新資源獨立於來源資源，則此類新資源的預設行為是它不為來源資源的應用程式所知（因為它不屬於所需狀態的一部分，也沒有 `ownerReference`）。
為了讓應用程式知道新資源，必須在資源上設定 `app.kubernetes.io/instance` 標籤（或如果已設定，則為其他 ArgoCD 追蹤標籤）。
可以從來源資源複製它，如下所示：

```lua
-- ...
newObj = {}
newObj.metadata = {}
newObj.metadata.labels = {}
newObj.metadata.labels["app.kubernetes.io/instance"] = obj.metadata.labels["app.kubernetes.io/instance"]
-- ...
```   

雖然新資源將成為具有追蹤標籤的應用程式的一部分，但如果應用程式設定了自動刪除，它將立即被刪除。
若要保留資源，請在資源上設定 `Prune=false` 註解，使用此 Lua 程式碼片段：

```lua
-- ...
newObj.metadata.annotations = {}
newObj.metadata.annotations["argocd.argoproj.io/sync-options"] = "Prune=false"
-- ...
```

（如果設定 `Prune=false` 行為，則資源在刪除應用程式時不會被刪除，並且需要手動清理）。

資源和應用程式現在將顯示為不同步 - 這是 ArgoCD 在建立不屬於所需狀態的資源時的預期行為。

如果您希望將此類應用程式視為已同步，請在 Lua 程式碼中新增以下資源註解：

```lua
-- ...
newObj.metadata.annotations["argocd.argoproj.io/compare-options"] = "IgnoreExtraneous"
-- ...
```

#### 產生資源清單的動作 - 一個完整的範例：

```yaml
resource.customizations.actions.ConfigMap: |
  discovery.lua: |
    actions = {}
    actions["do-things"] = {}
    return actions
  definitions:
  - name: do-things
    action.lua: |
      -- 建立一個新的 ConfigMap
      cm1 = {}
      cm1.apiVersion = "v1"
      cm1.kind = "ConfigMap"
      cm1.metadata = {}
      cm1.metadata.name = "cm1"
      cm1.metadata.namespace = obj.metadata.namespace
      cm1.metadata.labels = {}
      -- 複製 ArgoCD 追蹤標籤，以便資源被應用程式辨識
      cm1.metadata.labels["app.kubernetes.io/instance"] = obj.metadata.labels["app.kubernetes.io/instance"]
      cm1.metadata.annotations = {}
      -- 對於具有自動刪除的應用程式，在資源上設定 prune false，以免其被刪除
      cm1.metadata.annotations["argocd.argoproj.io/sync-options"] = "Prune=false"	  
      -- 即使應用程式具有不在 Git 中的資源，也保持應用程式同步
      cm1.metadata.annotations["argocd.argoproj.io/compare-options"] = "IgnoreExtraneous"		  
      cm1.data = {}
      cm1.data.myKey1 = "myValue1"
      impactedResource1 = {}
      impactedResource1.operation = "create"
      impactedResource1.resource = cm1

      -- 修補原始的 cm
      obj.metadata.labels["aKey"] = "aValue"
      impactedResource2 = {}
      impactedResource2.operation = "patch"
      impactedResource2.resource = obj

      result = {}
      result[1] = impactedResource1
      result[2] = impactedResource2
      return result		  
```

### 動作圖示和顯示名稱

預設情況下，動作將以 `actions` 金鑰中指定的名稱顯示在 UI 中，並且沒有圖示。您可以透過在動作定義中新增 `iconClass` 和 `displayName` 金鑰來自訂動作的顯示名稱和圖示。

圖示類別名稱是來自[免費圖示集](https://fontawesome.com/search?ic=free)的 FontAwesome 圖示名稱。`fa-fw` 類別可確保圖示以固定寬度顯示，以避免與其他圖示的對齊問題。

```lua
local actions = {}
actions["create-workflow"] = {
  ["iconClass"] = "fa fa-fw fa-plus",
  ["displayName"] = "Create Workflow"
}
return actions
```

### 動作參數

您可以為自訂動作定義參數。參數在動作發現定義的 `parameters` 金鑰中定義。

<!-- 直接連結到腳本，供在 GitHub 中閱讀文件的人使用，其中嵌入無法運作。 -->
請參閱 [Deployment 動作發現腳本](https://github.com/argoproj/argo-cd/blob/master/resource_customizations/apps/Deployment/actions/discovery.lua)：

<!-- 嵌入實際的腳本，以便 ReadTheDocs 始終有最新的範例。 -->
```lua
{!resource_customizations/apps/Deployment/actions/discovery.lua!}
```

[資源擴展動作](../user-guide/scale_application_resources.md)文件展示了此功能在 UI 中的行為方式。
