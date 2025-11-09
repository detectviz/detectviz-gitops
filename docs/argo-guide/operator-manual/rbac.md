# RBAC 設定

RBAC 功能可限制對 Argo CD 資源的存取。Argo CD 沒有自己的使用者管理系統，只有一個內建的 `admin` 使用者。`admin` 使用者是超級使用者，對系統擁有不受限制的存取權限。RBAC 需要[SSO 設定](user-management/index.md)或[設定一或多個本機使用者](user-management/index.md)。一旦設定了 SSO 或本機使用者，就可以定義額外的 RBAC 角色，然後可以將 SSO 群組或本機使用者對應到角色。

有兩個主要元件可以定義 RBAC 設定：

- 全域 RBAC 設定檔（請參閱 [argo-rbac-cm.yaml](argocd-rbac-cm-yaml.md)）
- [AppProject 的角色](../user-guide/projects.md#project-roles)

## 基本內建角色

Argo CD 有兩個預先定義的角色，但 RBAC 設定允許定義角色和群組（請參閱下文）。

- `role:readonly`：對所有資源的唯讀存取權限
- `role:admin`：對所有資源的不受限制存取權限

這些預設的內建角色定義可以在 [builtin-policy.csv](https://github.com/argoproj/argo-cd/blob/master/assets/builtin-policy.csv) 中看到

## 已驗證使用者的預設策略

當使用者在 Argo CD 中通過驗證時，將授予 `policy.default` 中指定的角色。

> [!WARNING]
> **限制預設權限**
>
> **所有已驗證的使用者至少會獲得預設策略授予的權限。此存取權限無法被 `deny` 規則封鎖。** 建議建立一個新的 `role:authenticated`，其權限盡可能少，然後根據需要授予個別角色的權限。

## 匿名存取

啟用對 Argo CD 執行個體的匿名存取可讓使用者**無需驗證**即可取得 `policy.default` 指定的預設角色權限。

可以使用 `argocd-cm` 中的 `users.anonymous.enabled` 欄位啟用對 Argo CD 的匿名存取（請參閱 [argocd-cm.yaml](argocd-cm.yaml.md)）。

> [!WARNING]
> 啟用匿名存取時，請考慮建立一個新的預設角色，並使用 `policy.default: role:unauthenticated` 將其指派給預設策略。

## RBAC 模型結構

模型語法基於 [Casbin](https://casbin.org/docs/overview)（一個開源的 ACL/ACLs）。有兩種不同的語法：一種用於指派策略，另一種用於將使用者指派給內部角色。

**群組**：允許將已驗證的使用者/群組指派給內部角色。

語法：`g, <user/group>, <role>`

- `<user/group>`：將被指派角色的實體。它可以是本機使用者或透過 SSO 驗證的使用者。使用 SSO 時，`user` 將基於 `sub` 宣告，而群組是 `scopes` 設定傳回的值之一。
- `<role>`：實體將被指派的內部角色。

**策略**：允許將權限指派給實體。

語法：`p, <role/user/group>, <resource>, <action>, <object>, <effect>`

- `<role/user/group>`：將被指派策略的實體
- `<resource>`：執行操作的資源類型。
- `<action>`：在資源上執行的操作。
- `<object>`：代表執行操作的資源的物件識別碼。根據資源的不同，物件的格式會有所不同。
- `<effect>`：此策略應授予還是限制對目標物件的操作。`allow` 或 `deny` 之一。

下表總結了所有可能的資源以及對每個資源有效的操作。

| 資源\操作 | get | create | update | delete | sync | action | override | invoke |
| :--- | :-: | :---: | :---: | :---: | :--: | :---: | :---: | :---: |
| **applications** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **applicationsets** | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **clusters** | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **projects** | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **repositories** | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **accounts** | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **certificates** | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **gpgkeys** | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **logs** | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **exec** | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **extensions** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |

### 特定於應用程式的策略

某些策略僅在應用程式內有意義。以下資源屬於這種情況：

- `applications`
- `applicationsets`
- `logs`
- `exec`

雖然它們可以在全域設定中設定，但也可以在 [AppProject 的角色](../user-guide/projects.md#project-roles)中設定。策略結構中預期的 `<object>` 值被 `<app-project>/<app-name>` 取代。

例如，這些策略將授予 `example-user` 取得任何應用程式的存取權限，但只能看到 `example-project` 專案中 `my-app` 應用程式的日誌。

```csv
p, example-user, applications, get, *, allow
p, example-user, logs, get, example-project/my-app, allow
```

#### 任何命名空間中的應用程式

啟用[任何命名空間中的應用程式](app-any-namespace.md)時，策略結構中預期的 `<object>` 值被 `<app-project>/<app-ns>/<app-name>` 取代。由於多個應用程式在同一個專案中可能具有相同的名稱，因此以下策略可確保僅將存取權限限制在 `app-namespace`。

```csv
p, example-user, applications, get, */app-namespace/*, allow
p, example-user, logs, get, example-project/app-namespace/my-app, allow
```

### `applications` 資源

`applications` 資源是一個[特定於應用程式的策略](#application-specific-policy)。

#### `update`/`delete` 操作的細微權限

`update` 和 `delete` 操作在授予應用程式時，將允許使用者對應用程式本身執行操作，但不能對其資源執行操作。

若要允許對應用程式的資源執行操作，請將操作指定為 `<action>/<group>/<kind>/<ns>/<name>`。

例如，若要授予 `example-user` 僅刪除 `prod-app` 應用程式中 Pod 的存取權限，策略可以是：

```csv
p, example-user, applications, delete/*/Pod/*/*, default/prod-app, allow
```

> [!WARNING]
> **了解 glob 模式的行為**
>
> Argo CD RBAC 在評估 glob 模式時不使用 `/` 作為分隔符。因此，模式 `delete/*/kind/*` 將匹配 `delete/<group>/kind/<namespace>/<name>`，但也匹配 `delete/<group>/<kind>/kind/<name>`。
>
> 這兩者都匹配通常不會造成問題，因為資源種類通常包含大寫字母，而命名空間不能包含大寫字母。但是，資源種類可能是小寫的。因此，最好始終在模式中包含資源的所有部分（換句話說，始終使用四個斜線）。

如果我們想授予使用者更新應用程式的所有資源，但不能更新應用程式本身的權限：

```csv
p, example-user, applications, update/*, default/prod-app, allow
```

如果我們想明確拒絕刪除應用程式，但允許使用者刪除 Pod：

```csv
p, example-user, applications, delete, default/prod-app, deny
p, example-user, applications, delete/*/Pod/*/*, default/prod-app, allow
```

如果我們想明確允許更新應用程式，但拒絕更新任何子資源：

```csv
p, example-user, applications, update, default/prod-app, allow
p, example-user, applications, update/*, default/prod-app, deny
```

> [!NOTE]
> **保留應用程式權限繼承（自 v3.0.0 起）**
>
> 在 v3 之前，`update` 和 `delete` 操作（不含 `/*`）也會在子資源上進行評估。
>
> 若要保留此行為，您可以在 Argo CD ConfigMap `argocd-cm` 中將組態值 `server.rbac.disableApplicationFineGrainedRBACInheritance` 設定為 `false`。
>
> 停用時，如果操作**已在應用程式上明確允許**，則無法拒絕子資源的細微權限。
> 例如，以下策略將**允許**使用者刪除 Pod 和應用程式中的任何其他資源：
>
> ```csv
> p, example-user, applications, delete, default/prod-app, allow
> p, example-user, applications, delete/*/Pod/*, default/prod-app, deny
> ```

#### `action` 操作

`action` 操作對應於[Argo CD 儲存庫](https://github.com/argoproj/argo-cd/tree/master/resource_customizations)中定義的內建資源自訂，或由您定義的[自訂資源操作](resource_actions.md#custom-resource-actions)。

有關內建操作的清單，請參閱[資源操作文件](resource_actions.md#built-in-actions)。

`<action>` 的格式為 `action/<group>/<kind>/<action-name>`。

例如，資源自訂路徑 `resource_customizations/extensions/DaemonSet/actions/restart/action.lua` 對應於 `action` 路徑 `action/extensions/DaemonSet/restart`。如果資源不屬於群組（例如 Pod 或 ConfigMap），則路徑將為 `action//Pod/action-name`。

以下策略允許使用者對 DaemonSet 資源執行任何操作，以及對 Pod 執行 `maintenance-off` 操作：

```csv
p, example-user, applications, action//Pod/maintenance-off, default/*, allow
p, example-user, applications, action/extensions/DaemonSet/*, default/*, allow
```

若要允許使用者執行任何操作：

```csv
p, example-user, applications, action/*, default/*, allow
```

#### `override` 操作

`override` 操作權限可用於允許在同步 `Application` 時傳遞任意清單或不同的修訂版本。這可用於開發或測試目的。

**注意：** 這允許使用者完全變更/刪除應用程式已部署的資源。

`sync` 操作權限賦予將叢集中的物件同步到 `Application` 物件中定義的所需狀態的權利，而 `override` 操作權限將允許使用者將任意的本機清單同步到應用程式。這些清單將被用來 _取代_ 已設定的來源，直到下一次同步執行。執行這樣的覆寫同步後，應用程式很可能會與 `Application` 物件定義的狀態不同步。
啟用自動同步時，無法執行 `override` 同步。

自 v3.2 起的新功能：

當在 `argcd-cm` configmap 中設定 `application.sync.requireOverridePrivilegeForRevisionSync: 'true'` 時，同步 `Application` 時傳遞修訂版本也被視為 `override`，以防止同步到 `Application` 物件中給定的修訂版本以外的任意修訂版本。與同步到任意 yaml 清單類似，同步到不同的修訂版本/分支/提交也會將受控物件帶到與 `Application` 中定義的狀態不同的狀態，因此會與其不同步。

此旗標的預設設定為 'false'，以防止在現有安裝中發生破壞性變更。建議將此設定設為 'true'，並僅將 `override` 權限授予每個 AppProject 實際需要此行為的使用者。
