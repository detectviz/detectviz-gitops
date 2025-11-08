# GnuPG 簽章驗證

## 概觀

自 v1.7 起，可以設定 ArgoCD 僅同步使用 GnuPG 在 Git 中簽署的提交。簽章驗證是在專案層級設定的。

如果專案設定為強制執行簽章驗證，則與此專案相關的所有應用程式都必須在來源儲存庫中使用 ArgoCD 已知的 GnuPG 公開金鑰簽署提交。ArgoCD 將拒絕同步到任何沒有由其中一個已設定金鑰所做有效簽章的修訂版本。如果控制器嘗試同步到未簽署或由未知或不允許的公開金鑰簽署的修訂版本，它將發出 `ResourceComparison` 錯誤。

預設情況下，簽章驗證已啟用但未強制執行。如果您希望在 ArgoCD 中完全停用 GnuPG 功能，您必須在 `argocd-server`、`argocd-repo-server`、`argocd-application-controller` 和 `argocd-applicationset-controller` 部署資訊清單的 pod 範本中將環境變數 `ARGOCD_GPG_ENABLED` 設定為 `"false"`。

GnuPG 簽章的驗證僅支援 Git 儲存庫。無法使用 Helm 儲存庫。

> [!NOTE]
> **關於信任的幾句話**
>
> ArgoCD 對您匯入的金鑰使用非常簡單的信任模型：一旦金鑰被匯入，ArgoCD 就會信任它。ArgoCD 不支援更複雜的信任模型，也不需要（也不可能）簽署您要匯入 ArgoCD 的公開金鑰。


> [!NOTE]
> 使用 Git 產生器時，不支援對範本化的 `project` 欄位進行簽章驗證。

## 簽章驗證目標

如果強制執行簽章驗證，ArgoCD 將使用以下策略驗證簽章：

* 如果 `target revision` 是指向提交物件的指標（即分支名稱、`HEAD` 等參考名稱或提交 SHA），ArgoCD 將對該名稱指向的提交物件（即提交）執行簽章驗證。

* 如果 `target revision` 解析為標籤且該標籤是輕量級標籤，則行為與 `target revision` 是指向提交物件的指標相同。但是，如果標籤是附加註解的，則目標修訂版本將指向*標籤*物件，因此，簽章驗證是在標籤物件上執行的，也就是說，標籤本身必須被簽署（使用 `git tag -s`）。

## 強制執行簽章驗證

若要設定強制執行簽章驗證，必須執行以下步驟：

* 在 ArgoCD 中匯入用於簽署提交的 GnuPG 公開金鑰
* 設定專案以強制執行給定金鑰的簽章驗證

一旦您為給定專案設定了一個或多個金鑰以進行驗證，則對與此專案相關的所有應用程式都將啟用強制執行。

> [!WARNING]
> 如果強制執行簽章驗證，您將無法再從本地來源同步（即 `argocd app sync --local`）。

## 管理 GnuPG 金鑰的 RBAC 規則

Argo CD 的 RBAC 實作中，允許管理 GnuPG 金鑰的適當資源表示法是 `gpgkeys`。

若要允許名為 `role:myrole` 的角色列出金鑰，請使用：

```
p, role:myrole, gpgkeys, get, *, allow
```

若要允許名為 `role:myrole` 的角色新增金鑰，請使用：

```
p, role:myrole, gpgkeys, create, *, allow
```

最後，若要允許名為 `role:myrole` 的角色刪除金鑰，請使用：

```
p, role:myrole, gpgkeys, delete, *, allow
```

## 匯入 GnuPG 公開金鑰

您可以使用 CLI、Web UI 或透過宣告式設定來設定 ArgoCD 將用於驗證提交簽章的 GnuPG 公開金鑰。

> [!NOTE]
> 匯入 GnuPG 金鑰後，金鑰可能需要一段時間才能在叢集中傳播，即使已列為已設定。如果您仍然無法同步到已匯入金鑰簽署的提交，請參閱下方的疑難排解部分。

想要管理 GnuPG 公開金鑰組態的使用者需要 `gpgkeys` 資源的 RBAC 權限。

### 使用 CLI 管理公開金鑰

若要使用 CLI 設定 GnuPG 公開金鑰，請使用 `argocd gpg` 指令。

#### 列出所有已設定的金鑰

若要列出 ArgoCD 已知的所有已設定金鑰，請使用 `argocd gpg list`
子指令：

```bash
argocd gpg list
```

#### 顯示某個金鑰的資訊

若要取得特定金鑰的資訊，請使用 `argocd gpg get` 子指令：

```bash
argocd gpg get <key-id>
```

#### 匯入金鑰

若要將新金鑰匯入 ArgoCD，請使用 `argocd gpg add` 子指令：

```bash
argocd gpg add --from <path-to-key>
```

要匯入的金鑰可以是二進位或 ASCII-armored 格式。

#### 從組態中移除金鑰

若要從組態中移除先前設定的金鑰，請使用
`argocd gpg rm` 子指令：

```bash
argocd gpg rm <key-id>
```

### 使用 Web UI 管理公開金鑰

Web UI 中實作了用於列出、匯入和移除 GnuPG
公開金鑰的基本金鑰管理功能。您可以從「設定」頁面的「GnuPG 金鑰」模組中找到組態
模組。

請注意，當您使用 Web UI 設定金鑰時，目前金鑰必須以 ASCII armored 格式匯入。

### 在宣告式設定中管理公開金鑰

ArgoCD 在 `argocd-gpg-keys-cm` ConfigMap
資源中內部儲存公開金鑰，以公開 GnuPG 金鑰的 ID 作為其名稱，並以 ASCII armored
金鑰資料作為字串值，即 GitHub 的 web-flow 簽署
金鑰的項目如下所示：

```yaml
4AEE18F83AFDEB23: |
    -----BEGIN PGP PUBLIC KEY BLOCK-----

    mQENBFmUaEEBCACzXTDt6ZnyaVtueZASBzgnAmK13q9Urgch+sKYeIhdymjuMQta
    x15OklctmrZtqre5kwPUosG3/B2/ikuPYElcHgGPL4uL5Em6S5C/oozfkYzhwRrT
    SQzvYjsE4I34To4UdE9KA97wrQjGoz2Bx72WDLyWwctD3DKQtYeHXswXXtXwKfjQ

    7Fy4+Bf5IPh76dA8NJ6UtjjLIDlKqdxLW4atHe6xWFaJ+XdLUtsAroZcXBeWDCPa
    buXCDscJcLJRKZVc62gOZXXtPfoHqvUPp3nuLA4YjH9bphbrMWMf810Wxz9JTd3v
    yWgGqNY0zbBqeZoGv+TuExlRHT8ASGFS9SVDABEBAAG0NUdpdEh1YiAod2ViLWZs
    b3cgY29tbWl0IHNpZ25pbmcpIDxub3JlcGx5QGdpdGh1Yi5jb20+iQEiBBMBCAAW
    BQJZlGhBCRBK7hj4Ov3rIwIbAwIZAQAAmQEH/iATWFmi2oxlBh3wAsySNCNV4IPf
    DDMeh6j80WT7cgoX7V7xqJOxrfrqPEthQ3hgHIm7b5MPQlUr2q+UPL22t/I+ESF6
    9b0QWLFSMJbMSk+BXkvSjH9q8jAO0986/pShPV5DU2sMxnx4LfLfHNhTzjXKokws
    +8ptJ8uhMNIDXfXuzkZHIxoXk3rNcjDN5c5X+sK8UBRH092BIJWCOfaQt7v7wig5
    4Ra28pM9GbHKXVNxmdLpCFyzvyMuCmINYYADsC848QQFFwnd4EQnupo6QvhEVx1O
    j7wDwvuH5dCrLuLwtwXaQh0onG4583p0LGms2Mf5F+Ick6o/4peOlBoZz48=
    =Bvzs
    -----END PGP PUBLIC KEY BLOCK-----
```

## 設定專案以強制執行簽章驗證

將 GnuPG 金鑰匯入 ArgoCD 後，您現在必須設定
專案以強制使用匯入的金鑰驗證提交簽章。

### 使用 CLI 設定

#### 將金鑰 ID 新增至允許的金鑰清單

若要將金鑰 ID 新增至專案的允許 GnuPG 金鑰清單，您可以使用
`argocd proj add-signature-key` 指令，例如，以下指令會將
金鑰 ID `4AEE18F83AFDEB23` 新增至名為 `myproj` 的專案：

```bash
argocd proj add-signature-key myproj 4AEE18F83AFDEB23
```

#### 從允許的金鑰清單中移除金鑰 ID

同樣地，您可以使用 `argocd proj remove-signature-key` 指令，從專案的允許 GnuPG 金鑰清單中移除金鑰 ID，例如，若要從 `myproj` 專案中移除上述新增的金鑰，請使用以下指令：

```bash
argocd proj remove-signature-key myproj 4AEE18F83AFDEB23
```

#### 顯示專案允許的金鑰 ID

若要查看給定專案允許哪些金鑰 ID，您可以檢查
`argocd proj get` 指令的輸出，例如，對於名為 `gpg` 的專案：

```bash
$ argocd proj get gpg
Name:                        gpg
Description:                 GnuPG verification
Destinations:                *,*
Repositories:                *
Allowed Cluster Resources:   */*
Denied Namespaced Resources: <none>
Signature keys:              4AEE18F83AFDEB23, 07E34825A909B250
Orphaned Resources:          disabled
```

#### 覆寫金鑰 ID 清單

您也可以使用 `argocd proj set` 指令搭配 `--signature-keys`
旗標，明確地將目前允許的金鑰設定為一個或多個新金鑰，
您可以使用此旗標來指定以逗號分隔的允許金鑰 ID 清單：

```bash
argocd proj set myproj --signature-keys 4AEE18F83AFDEB23,07E34825A909B250
```

`--signature-keys` 旗標也可以在專案建立時使用，例如
`argocd proj create` 指令。

### 使用 Web UI 設定

您可以使用 Web UI 在專案組態中設定簽章驗證所需的 GnuPG 金鑰 ID。請導覽至「設定」頁面，然後選取「專案」模組，再按一下您要設定的專案。

在專案的詳細資料頁面中，按一下「編輯」，然後找到「必要的簽章金鑰」區段，您可以在其中新增或移除簽章驗證的金鑰 ID。修改專案後，按一下「更新」以儲存變更。

### 使用宣告式設定

您可以在 `signatureKeys` 區段內的專案
資訊清單中指定簽章驗證所需的金鑰 ID，例如：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: gpg
  namespace: argocd
spec:
  clusterResourceWhitelist:
  - group: '*'
    kind: '*'
  description: GnuPG verification
  destinations:
  - namespace: '*'
    server: '*'
  namespaceResourceWhitelist:
  - group: '*'
    kind: '*'
  signatureKeys:
  - keyID: 4AEE18F83AFDEB23
  sourceRepos:
  - '*'
```

`signatureKeys` 是 `SignatureKey` 物件的陣列，目前其唯一的屬性是
`keyID`。

## 疑難排解

### 停用此功能

如果需要，可以完全停用 GnuPG 功能。若要停用它，
請將 `argocd-server`、`argocd-repo-server`、`argocd-application-controller`
和 `argocd-applicationset-controller` 部署的 pod 範本的環境變數 `ARGOCD_GPG_ENABLED` 設定為 `false`。

重新啟動 pod 後，GnuPG 功能即被停用。

### GnuPG 金鑰環

用於簽章驗證的 GnuPG 金鑰環是在 `argocd-repo-server`
的 pod 中維護的。金鑰環中的金鑰會與儲存在 `argocd-gpg-keys-cm` ConfigMap 資源中的組態同步，
該資源會以磁碟區方式掛載到 `argocd-repo-server` 的 pod 中。

> [!NOTE]
> Pod 中的 GnuPG 金鑰環是暫時性的，每次重新啟動 pod 時都會從
> 組態中重新建立。您絕對不應手動將金鑰新增或移除到金鑰環中，因為您的變更將會遺失。此外，
> 金鑰環中找到的任何私鑰都是暫時性的，每次重新啟動時都會
> 重新產生。私鑰僅用於為執行中的 pod 建立
> 信任資料庫。

若要檢查金鑰是否確實同步，您可以 `kubectl exec` 進入
儲存庫伺服器的 pod 並檢查金鑰環，其位於
`/app/config/gpg/keys`

```bash
$ kubectl exec -it argocd-repo-server-7d6bdfdf6d-hzqkg bash
argocd@argocd-repo-server-7d6bdfdf6d-hzqkg:~$ GNUPGHOME=/app/config/gpg/keys gpg --list-keys
/app/config/gpg/keys/pubring.kbx
--------------------------------
pub   rsa2048 2020-06-15 [SC] [expires: 2020-12-12]
      D48F075D818A813C436914BC9324F0D2144753B1
uid           [ultimate] Anon Ymous (ArgoCD key signing key) <noreply@argoproj.io>

pub   rsa2048 2017-08-16 [SC]
      5DE3E0509C47EA3CF04A42D34AEE18F83AFDEB23
uid           [ultimate] GitHub (web-flow commit signing) <noreply@github.com>

argocd@argocd-repo-server-7d6bdfdf6d-hzqkg:~$
```

如果您新增或移除金鑰後，金鑰環在一段較長的時間內仍與您的組態不同步，您可能需要重新啟動您的
`argocd-repo-server` pod。如果此類問題持續存在，請考慮提出
錯誤報告。
