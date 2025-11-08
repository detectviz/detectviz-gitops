# 來源 Hydrator

**目前功能狀態**：Alpha

像 Helm 和 Kustomize 這樣的工具允許使用者以更簡潔和可重複使用的方式表達他們的 Kubernetes 資訊清單（保持 DRY - Don't Repeat Yourself）。然而，這些工具可能會掩蓋實際應用於叢集的 Kubernetes 資訊清單。

「渲染資訊清單模式」是 Argo CD 的一項功能，它允許使用者在將渲染後的資訊清單同步到叢集之前將其推送到 git。這讓使用者可以看到實際應用於叢集的 Kubernetes 資訊清單。

## 啟用來源 Hydrator

來源 hydrator 預設為停用。

若要啟用來源 hydrator，您需要啟用「commit server」元件，並在 argocd-cmd-params-cm ConfigMap 中將 `hydrator.enabled` 欄位設定為 `"true"`。

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cmd-params-cm
  namespace: argocd
data:
  hydrator.enabled: "true"
```

> [!IMPORTANT]
> 更新 ConfigMap 後，您必須重新啟動 Argo CD 控制器和 API 伺服器，變更才會生效。

如果您使用 `*-install.yaml` 資訊清單之一來安裝 Argo CD，您可以改用該檔案的 `*-install-with-hydrator.yaml` 版本。

例如，

```
不含 hydrator：https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
含 hydrator：   https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install-with-hydrator.yaml
```

> [!IMPORTANT]
> 當來源 hydrator 預設啟用或被移除時，`*-with-hydrator-install.yaml` 資訊清單最終將被移除。如果 `install-with-hydrator.yaml` 資訊清單不再可用，升級指南將會註明。

## 使用來源 Hydrator

若要使用來源 hydrator，您必須先安裝一個推送和一個拉取密鑰。本範例使用 GitHub App 進行身份驗證，但您可以使用 [Argo CD 支援的任何用於儲存庫存取的身份驗證方法](../operator-manual/declarative-setup.md#repositories)。

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: my-push-secret
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository-write
type: Opaque
stringData:
  url: "https://github.com"
  type: "git"
  githubAppID: "<your app ID here>"
  githubAppInstallationID: "<your installation ID here>"
  githubAppPrivateKey: |
    <your private key here>
---
apiVersion: v1
kind: Secret
metadata:
  name: my-pull-secret
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
  url: "https://github.com"
  type: "git"
  githubAppID: "<your app ID here>"
  githubAppInstallationID: "<your installation ID here>"
  githubAppPrivateKey: |
    <your private key here>
```

除了資源名稱外，上述密鑰之間唯一的區別是，推送密鑰包含標籤 `argocd.argoproj.io/secret-type: repository-write`，這會導致該密鑰用於將資訊清單推送到 git，而不是從 git 拉取。Argo CD 要求推送和拉取使用不同的密鑰，以提供更好的隔離。

安裝密鑰後，設定 Application 的 `spec.sourceHydrator` 欄位。例如：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
spec:
  sourceHydrator:
    drySource:
      repoURL: https://github.com/argoproj/argocd-example-apps
      path: helm-guestbook
      targetRevision: HEAD
    syncSource:
      targetBranch: environments/dev
      path: helm-guestbook
```

在此範例中，渲染後的資訊清單將被推送到 `argocd-example-apps` 儲存庫的 `environments/dev` 分支。

使用來源渲染時，`syncSource.path` 欄位是必要的，且必須始終指向儲存庫中的非根目錄。不支援將路徑設定為儲存庫根目錄（例如 `"."` 或 `""`）。這可確保渲染始終限定於專用子目錄，從而避免無意中覆寫或移除可能存在於儲存庫根目錄中的檔案。

在每次渲染執行期間，Argo CD 會在寫出新產生的資訊清單之前清理應用程式設定的路徑。這可以保證先前渲染的舊檔案或過時檔案不會殘留在輸出目錄中。然而，儲存庫根目錄永遠不會被清理，因此諸如 CI/CD 組態、README 檔案或其他根層級資產等檔案將保持不變。

請務必注意，渲染僅清理目前設定的應用程式路徑。如果應用程式的路徑變更，舊目錄不會自動移除。同樣，如果刪除應用程式，其輸出路徑會保留在儲存庫中，如果需要，必須由儲存庫擁有者手動清理。此設計是刻意的：它可防止在重組或移除應用程式時意外刪除檔案，並保護可能共存於儲存庫中的 CI 管線等關鍵檔案。

> [!IMPORTANT]
> **專案範圍的儲存庫**
>
> 儲存庫密鑰可能包含 `project` 欄位，使該密鑰僅能由該專案中的應用程式使用。
> 來源 hydrator 僅在寫入相同儲存庫和分支的所有應用程式都位於相同專案中時，才支援專案範圍的儲存庫。如果不同專案中的應用程式寫入相同的儲存庫和分支，來源 hydrator 將無法使用專案範圍的儲存庫密鑰，並且需要一個全域儲存庫密鑰。此行為未來可能會變更。

如果有多個 repository-write Secrets 可用於一個儲存庫，來源 hydrator 將不確定地選擇一個相符的 Secret，並記錄一則警告訊息「Found multiple credentials for repoURL」。

## 推送到「預備」分支

來源 hydrator 可用於將渲染後的資訊清單推送到「預備」分支，而不是 `syncSource` 分支。這提供了一種方法，可以在滿足某些先決條件之前，防止將渲染後的資訊清單應用於叢集（實際上是透過拉取請求處理環境升級的一種方式）。

若要使用來源 hydrator 將其推送到「預備」分支，請設定 Application 的 `spec.sourceHydrator.hydrateTo` 欄位。例如：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
spec:
  project: my-project
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  sourceHydrator:
    drySource:
      repoURL: https://github.com/argoproj/argocd-example-apps
      path: helm-guestbook
      targetRevision: HEAD
    syncSource:
      targetBranch: environments/dev
      path: helm-guestbook
    hydrateTo:
      targetBranch: environments/dev-next
```

在此範例中，渲染後的資訊清單將被推送到 `environments/dev-next` 分支，Argo CD 將不會同步變更，直到有東西將它們移動到 `environments/dev` 分支。

您可以使用 CI 動作將渲染後的資訊清單從 `hydrateTo` 分支移動到 `syncSource` 分支。若要引入閘門機制，您可以要求開啟一個拉取請求，以將變更從 `hydrateTo` 分支合併到 `syncSource` 分支。

Argo CD 只會將變更推送到 `hydrateTo` 分支，它不會建立 PR 或以其他方式促進將這些變更移動到 `syncSource` 分支。您需要使用自己的工具將變更從 `hydrateTo` 分支移動到 `syncSource` 分支。

## 提交追蹤

CI 或其他工具在程式碼變更後推送 DRY 資訊清單變更是很常見的。使用者能夠將渲染後的提交追溯到導致渲染的原始程式碼變更非常重要。

Source Hydrator 利用一些自訂的 git 提交尾註來促進此追蹤。一個 CI 工作，它建立一個映像檔並將映像檔更新推送到 DRY 資訊清單，可以使用以下提交尾註將渲染後的提交連結到程式碼提交。

```shell
git commit -m "Bump image to v1.2.3" \
  # 必須是 RFC 5322 名稱
  --trailer "Argocd-reference-commit-author: Author Name <author@example.com>" \
  # 必須是 5-40 個字元的十六進位字串
  --trailer "Argocd-reference-commit-sha: <code-commit-sha>" \
  # 主旨是提交訊息的第一行。它不能包含換行符。
  --trailer "Argocd-reference-commit-subject: Commit message of the code commit" \
   # 內文必須是有效的 JSON 字串，包括開頭和結尾的引號
  --trailer 'Argocd-reference-commit-body: "Commit message of the code commit\n\nSigned-off-by: Author Name <author@example.com>"' \
   # repo URL 必須是有效的 URL
  --trailer "Argocd-reference-commit-repourl: https://git.example.com/owner/repo" \
  # 日期必須是 ISO 8601 格式
  --trailer "Argocd-reference-commit-date: 2025-06-09T13:50:18-04:00"
```

> [!NOTE]
> 提交尾註不得包含換行符。

因此，完整的 CI 指令碼可能如下所示：

```shell
# 複製程式碼儲存庫
git clone https://git.example.com/owner/repo.git
cd repo

# 建立映像檔並取得新的映像檔標籤
# <custom build logic here>

# 取得提交資訊
author=$(git show -s --format="%an <%ae>")
sha=$(git rev-parse HEAD)
subject=$(git show -s --format='%s')
body=$(git show -s --format='%b')
jsonbody=$(jq -n --arg body "$body" '$body')
repourl=$(git remote get-url origin)
date=$(git show -s --format='%aI')

# 複製 dry source 儲存庫
git clone https://git.example.com/owner/deployment-repo.git
cd deployment-repo

# 在 dry manifests 中更新映像檔
# <custom bump logic here, e.g. `kustomize edit`>

# 使用提交尾註提交變更
git commit -m "Bump image to v1.2.3" \
  --trailer "Argocd-reference-commit-author: $author" \
  --trailer "Argocd-reference-commit-sha: $sha" \
  --trailer "Argocd-reference-commit-subject: $subject" \
  --trailer "Argocd-reference-commit-body: $jsonbody" \
  --trailer "Argocd-reference-commit-repourl: $repourl" \
  --trailer "Argocd-reference-commit-date: $date"
```

提交元資料將出現在渲染後的提交的根 hydrator.metadata 檔案中：

```json
{
  "author": "CI <ci@example.com>",
  "subject": "chore: bump image to b82add2",
  "date": "2025-06-09T13:50:08-04:00",
  "body": "Signed-off-by: CI <ci@example.com>\n",
  "drySha": "6cb951525937865dced818bbdd78c89b2d2b3045",
  "repoURL": "https://git.example.com/owner/manifests-repo",
  "references": [
    {
      "commit": {
        "author": {
          "name": "Author Name",
          "email": "author@example.com"
        },
        "sha": "b82add298aa045d3672880802d5305c5a8aaa46e",
        "subject": "chore: make a change",
        "body": "make a change\n\nSigned-off-by: Author Name <author@example.com>",
        "repoURL": "https://git.example.com/owner/repo",
        "date": "2025-06-09T13:50:18-04:00"
      }
    }
  ]
}
```

頂層的「body」欄位包含 DRY 提交的提交訊息，減去主旨行和 `references` 中使用的任何 `Argocd-reference-commit-*` 尾註。無法辨識或無效的尾註會保留在內文中。

雖然 `references` 是一個陣列，但來源 hydrator 目前只支援一個相關的提交。如果一個尾註被指定了多次，將使用最後一個。

所有尾註都是可選的。如果未指定尾註，元資料中的相應欄位將被省略。

## 提交訊息範本

提交訊息是使用 [Go text/template](https://pkg.go.dev/text/template) 產生的，可由使用者透過 argocd-cm ConfigMap 選擇性地設定。範本是使用 `hydrator.metadata` 中的值來渲染的。範本可以是多行的，允許使用者定義主旨行、內文和可選的尾註。若要定義提交訊息範本，您需要在 argocd-cm ConfigMap 中設定 `sourceHydrator.commitMessageTemplate` 欄位。

範本可以使用 [Sprig 函數庫](https://github.com/Masterminds/sprig) 中的函數。

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  sourceHydrator.commitMessageTemplate: |
    {{.metadata.drySha | trunc 7}}: {{ .metadata.subject }}
    {{- if .metadata.body }}
    
    {{ .metadata.body }}
    {{- end }}
    {{ range $ref := .metadata.references }}
    {{- if and $ref.commit $ref.commit.author }}
    Co-authored-by: {{ $ref.commit.author }}
    {{- end }}
    {{- end }}
    {{- if .metadata.author }}
    Co-authored-by: {{ .metadata.author }}
    {{- end }}
```

### 憑證範本

憑證範本允許將單一憑證用於多個儲存庫。來源 hydrator 支援憑證範本。例如，如果您為 URL 前綴 `https://github.com/argoproj` 設定憑證範本，這些憑證將用於所有以此 URL 為前綴的儲存庫（例如 `https://github.com/argoproj/argocd-example-apps`），前提是它們沒有設定自己的憑證。
有關更多資訊，請參閱 [credential-template](private-repositories.md#credential-templates)。
repo-write-creds secret 的一個範例。

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: private-repo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repo-write-creds
stringData:
  type: git
  url: https://github.com/argoproj
  password: my-password
  username: my-username
```

## 限制

### 簽章驗證

來源 hydrator **目前不支援其渲染/提交的 DRY 來源的簽章驗證**。它也不會對其推送到 git 的提交進行簽署，因此如果啟用了簽章驗證，當 Argo CD 嘗試同步渲染後的資訊清單時，提交將會驗證失敗。

### 專案範圍的推送密鑰

如果給定目標儲存庫/分支的所有應用程式都在同一個專案下，則 hydrator 將使用任何可用的專案範圍的推送密鑰。如果給定儲存庫/分支的兩個應用程式位於不同的專案中，則 hydrator 將無法使用專案範圍的推送密鑰，並且需要一個全域推送密鑰。

### `manifest-generate-paths` 註解支援

來源 hydrator 目前不支援 [manifest-generate-paths annotation](../operator-manual/high_availability.md#manifest-paths-annotation) 來避免對 dry commits 進行渲染。換句話說，來源 hydrator 無法略過未變更相關檔案的 dry commits 的渲染。

應用程式控制器在同步渲染後的資訊清單時*確實*會遵守 `manifest-generate-paths` 註解。因此，如果您的應用程式渲染到 `foo` 目錄，並且 `manifest-generate-paths` 註解設定為 `foo`，那麼在僅影響 `bar` 目錄中檔案的提交後，應用程式控制器將不會重新渲染資訊清單。

## 先決條件

### 在目標叢集上處理密鑰

不要將來源 hydrator 與任何在渲染過程中將密鑰注入您的資訊清單的工具一起使用（例如，使用 SOPS 的 Helm 或 Argo CD Vault Plugin）。這些密鑰將會被提交到 git。相反，請使用一個 secrets operator，它會在目標叢集上填入密鑰值。

## 最佳實踐

### 使渲染具確定性

來源 hydrator 應該是確定性的。對於給定的 dry source commit，hydrator 應該總是產生相同的渲染後資訊清單。這意味著 hydrator 不應依賴於未儲存在 git 中的外部狀態或組態。

非確定性渲染的範例：

* 使用未固定相依項目的 Helm 圖表
* 使用非確定性範本函數（例如 `randAlphaNum` 或 `lookup`）的 Helm 圖表
* 擷取非 git 狀態（例如密鑰）的[組態管理外掛程式](../operator-manual/config-management-plugins.md)
* 參照未固定遠端基礎的 Kustomize 資訊清單

### 啟用分支保護

Argo CD 應該是唯一將渲染後的資訊清單推送到渲染後分支的東西。為防止其他工具或使用者推送到渲染後的分支，請在您的 SCM 中啟用分支保護。

最佳實踐是為渲染後的分支加上一個共同的前綴，例如 `environments/`。這使得在目標儲存庫上設定分支保護規則更容易。

> [!NOTE]
> 為了在 Hydrator 的輸出中保持可重複性和確定性，
> Argo CD 特定的元資料（例如 `argocd.argoproj.io/tracking-id`）在渲染期間不會寫入 Git。這些註解是在應用程式同步和比較期間動態新增的。
