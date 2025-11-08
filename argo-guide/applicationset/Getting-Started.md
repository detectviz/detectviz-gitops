# 入門指南

本指南假設您熟悉 Argo CD 及其基本概念。如需更多資訊，請參閱 [Argo CD 文件](../../core_concepts.md)。

## 需求

* 已安裝 [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) 命令列工具
* 擁有 [kubeconfig](https://kubernetes.io/docs/tasks/access-application-cluster/configure-access-multiple-clusters/) 檔案（預設位置為 `~/.kube/config`）。

## 安裝

安裝 ApplicationSet 控制器有幾種選項。


### A) 將 ApplicationSet 作為 Argo CD 的一部分安裝

從 Argo CD v2.3 開始，ApplicationSet 控制器與 Argo CD 捆綁在一起。不再需要與 Argo CD 分開安裝 ApplicationSet 控制器。

如需更多資訊，請遵循 [Argo CD 入門](../../getting_started.md) 說明。



### B) 將 ApplicationSet 安裝到現有的 Argo CD 安裝中（Argo CD v2.3 之前）

**注意**：這些說明僅適用於 Argo CD v2.3.0 之前的版本。

ApplicationSet 控制器**必須**安裝到與其目標 Argo CD 相同的命名空間中。

假設 Argo CD 已安裝到 `argocd` 命名空間中，請執行以下命令：

```bash
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/applicationset/v0.4.0/manifests/install.yaml
```

安裝後，ApplicationSet 控制器無需額外設定。

`manifests/install.yaml` 檔案包含安裝 ApplicationSet 控制器所需的 Kubernetes 資訊清單：

- `ApplicationSet` 資源的 CustomResourceDefinition
- `argocd-applicationset-controller` 的 Deployment
- ApplicationSet 控制器使用的 ServiceAccount，以存取 Argo CD 資源
- 授予 ServiceAccount 所需資源 RBAC 存取權限的 Role
- 將 ServiceAccount 和 Role 綁定的 RoleBinding


<!-- ### C) 安裝 ApplicationSet 控制器的開發版本以存取最新功能

可以透過執行以下命令來安裝 ApplicationSet 控制器的開發版本：
```bash
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/applicationset/master/manifests/install.yaml
```

使用此選項，您需要確保 Argo CD 已安裝到 `argocd` 命名空間中。

運作方式：

- 在每次成功提交到 *argoproj/applicationset* `master` 分支後，將執行一個 GitHub 動作，該動作會將容器建置/推送到 [`argoproj/argocd-applicationset:latest`](https://quay.io/repository/argoproj/argocd-applicationset?tab=tags )
- Read the Docs 上提供了[基於 `master` 分支的開發人員版本的說明文件](https://argocd-applicationset.readthedocs.io/en/master/)。

> [!WARNING]
> 開發版本包含較新的功能和錯誤修正，但與發行版本相比，可能更不穩定。

有關發行後功能的說明文件，請參閱 `master` 分支 [Read the Docs](https://argocd-applicationset.readthedocs.io/en/master/) 頁面。 -->


<!-- ## 升級到較新版本

若要從較舊的版本（例如 0.1.0、0.2.0）升級到較新的版本（例如 0.3.0），您只需要如上所述的*安裝*部分中所述，`kubectl apply` 新版本的 `install.yaml` 即可。

截至本文撰寫時，ApplicationSet 控制器的任何版本之間（包括 0.1.0、0.2.0 和 0.3.0）都不需要手動升級步驟，但是，請參閱下方 ApplicationSet 控制器 v0.3.0 中的行為變更。

### ApplicationSet 控制器 v0.3.0 中的行為變更

沒有重大變更，但是，從 v0.2.0 到 v0.3.0，有幾個行為已變更。詳情請參閱 [v0.3.0 升級頁面](upgrading/v0.2.0-to-v0.3.0.md)。 -->
## 啟用高可用性模式

若要啟用高可用性，您必須在 argocd-applicationset-controller 容器中設定命令 ``` --enable-leader-election=true  ``` 並增加複本數。

在 manifests/install.yaml 中進行以下變更

```bash
    spec:
      containers:
      - command:
        - entrypoint.sh
        - argocd-applicationset-controller
        - --enable-leader-election=true
```

### 可選：額外的升級後保障措施

有關您可能希望新增到 `install.yaml` 中 ApplicationSet 資源的額外參數的資訊，請參閱[控制資源修改](Controlling-Resource-Modification.md) 頁面，以提供額外的安全性，以防任何初始的、意外的升級後行為。

例如，若要暫時防止升級後的 ApplicationSet 控制器進行任何變更，您可以：

- 啟用試執行
- 使用僅建立原則
- 在您的 ApplicationSets 上啟用 `preserveResourcesOnDeletion`
- 在您的 ApplicationSets 的範本中暫時停用自動同步

這些參數可讓您觀察/控制新版 ApplicationSet 控制器在您環境中的行為，以確保您對結果感到滿意（有關詳細資訊，請參閱 ApplicationSet 記錄檔）。只是不要忘記在完成測試後移除任何臨時變更！

但是，如上所述，這些步驟並非絕對必要：升級 ApplicationSet 控制器應該是一個微創的過程，這些僅建議作為額外安全性的可選預防措施。

## 後續步驟

一旦您的 ApplicationSet 控制器啟動並執行，請繼續閱讀[使用案例](Use-Cases.md)以了解有關支援的方案的更多資訊，或直接前往[產生器](Generators.md)以查看 `ApplicationSet` 資源的範例。
