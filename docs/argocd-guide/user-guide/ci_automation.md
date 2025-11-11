# CI 管線的自動化

Argo CD 遵循 GitOps 部署模型，其中期望的組態變更首先
推送到 Git，然後叢集狀態同步到 Git 中的期望狀態。這與
傳統上不使用 Git 儲存庫來存放應用程式
組態的命令式管線有所不同。

若要將新的容器映像檔推送到由 Argo CD 管理的叢集，可以使用以下工作流程（或
其變體）：

## 建置並發布新的容器映像檔

```bash
docker build -t mycompany/guestbook:v2.0 .
docker push mycompany/guestbook:v2.0
```

## 使用您偏好的範本工具更新本地資訊清單，並將變更推送到 Git

> [!TIP]
> 強烈建議使用不同的 Git 儲存庫來存放您的 Kubernetes 資訊清單（與您的
> 應用程式原始碼分開）。更多理由請參閱[最佳實踐](best_practices.md)。

```bash
git clone https://github.com/mycompany/guestbook-config.git
cd guestbook-config

# kustomize
kustomize edit set image mycompany/guestbook:v2.0

# plain yaml
kubectl patch --local -f config-deployment.yaml -p '{"spec":{"template":{"spec":{"containers":[{"name":"guestbook","image":"mycompany/guestbook:v2.0"}]}}}}' -o yaml > config-deployment.yaml

git commit -am "Update guestbook to v2.0"
git push
```

## 同步應用程式（可選）

為方便起見，可以直接從 API 伺服器下載 argocd CLI。這很
有用，因為 CI 管線中使用的 CLI 始終保持同步，並且使用的 argocd 二進位檔
始終與 Argo CD API 伺服器相容。

```bash
export ARGOCD_SERVER=argocd.example.com
export ARGOCD_AUTH_TOKEN=<JWT token generated from project>
curl -sSL -o /usr/local/bin/argocd https://${ARGOCD_SERVER}/download/argocd-linux-amd64
argocd app sync guestbook
argocd app wait guestbook
```

如果為應用程式設定了[自動同步](auto_sync.md)，則此步驟
非必要。控制器將自動偵測到新的組態（使用
[webhook](../operator-manual/webhook.md) 快速追蹤，或預設至少每 3 分鐘輪詢一次），並自動同步新的資訊清單。
