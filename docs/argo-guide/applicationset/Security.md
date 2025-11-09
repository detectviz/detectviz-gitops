# ApplicationSet 安全性

ApplicationSet 是一個功能強大的工具，在使用之前了解其安全性至關重要。

## 只有管理員可以建立/更新/刪除 ApplicationSets

ApplicationSets 可以在任意[專案](../../user-guide/projects.md)下建立應用程式。Argo CD 的設定通常包含具有高權限等級的專案（例如 `default`），通常包括管理 Argo CD 本身資源的能力（例如 RBAC ConfigMap）。

ApplicationSets 也可以快速建立任意數量的應用程式，並同樣快速地刪除它們。

最後，ApplicationSets 可能會洩漏特權資訊。例如，[git 產生器](./Generators-Git.md)可以讀取 Argo CD 命名空間中的 Secrets，並將其作為驗證標頭傳送到任意 URL（例如，為 `api` 欄位提供的 URL）。（此功能旨在授權對 GitHub 等 SCM 提供者的請求，但可能會被惡意使用者濫用。）

基於這些原因，**只有管理員**才能被授予（透過 Kubernetes RBAC 或任何其他機制）建立、更新或刪除 ApplicationSets 的權限。

## 管理員必須對 ApplicationSets 的事實來源應用適當的控制

即使非管理員無法建立 ApplicationSet 資源，他們也可能能夠影響 ApplicationSets 的行為。

例如，如果 ApplicationSet 使用 [git 產生器](./Generators-Git.md)，具有對來源 git 儲存庫推送權限的惡意使用者可能會產生過多的應用程式，從而對 ApplicationSet 和應用程式控制器造成壓力。他們也可能導致 SCM 提供者的速率限制生效，從而降低 ApplicationSet 服務的品質。

### 範本化的 `project` 欄位

特別注意 `project` 欄位被範本化的 ApplicationSets 非常重要。對產生器的事實來源具有寫入權限的惡意使用者（例如，對 git 產生器的 git 儲存庫具有推送權限的人）可能會在限制不足的專案下建立應用程式。能夠在不受限制的專案（例如 `default` 專案）下建立應用程式的惡意使用者，可能會透過（例如）修改其 RBAC ConfigMap 來控制 Argo CD 本身。

如果 `project` 欄位未在 ApplicationSet 的範本中硬式編碼，則管理員**必須**控制 ApplicationSet 產生器的所有事實來源。
