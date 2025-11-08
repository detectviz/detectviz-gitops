# 最佳實踐

## 分離組態與原始碼儲存庫

強烈建議使用一個獨立的 Git 儲存庫來存放您的 Kubernetes 資訊清單，將組態與您的應用程式原始碼分開，原因如下：

1. 它提供了應用程式程式碼與應用程式組態的清晰分離。有時候您只想修改資訊清單，而不想觸發整個 CI 建置。例如，如果您只想增加部署規格中的副本數量，您可能*不*希望觸發建置。

2. 更乾淨的稽核日誌。出於稽核目的，僅存放組態的儲存庫將會有一個更乾淨的 Git 歷史記錄，其中包含所做的變更，而沒有正常開發活動簽入所帶來的雜訊。

3. 您的應用程式可能包含由多個 Git 儲存庫建置的服務，但會作為一個單一部署。通常，微服務應用程式包含具有不同版本控制方案和發布週期的服務（例如 ELK、Kafka + ZooKeeper）。將資訊清單儲存在單一元件的其中一個原始碼儲存庫中可能沒有意義。

4. 存取權限的分離。開發應用程式的開發人員不一定是有權限/應該推送到生產環境的人員，無論是有意還是無意。透過擁有獨立的儲存庫，可以將提交存取權限授予原始碼儲存庫，而不是應用程式組態儲存庫。

5. 如果您正在自動化 CI 管線，將資訊清單變更推送到同一個 Git 儲存庫可能會觸發建置作業和 Git 提交觸發器的無限循環。擁有一個獨立的儲存庫來推送組態變更可以防止這種情況發生。


## 為命令式保留空間

可能需要為某些命令式/自動化保留空間，而不是將所有內容都定義在您的 Git 資訊清單中。例如，如果您希望部署的副本數量由[水平 Pod 自動擴展器](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)管理，那麼您就不會在 Git 中追蹤 `replicas`。

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  # 如果您希望副本由 HPA 控制，請不要在資訊清單中包含 replicas
  # replicas: 1
  template:
    spec:
      containers:
      - image: nginx:1.7.9
        name: nginx
        ports:
        - containerPort: 80
...
```

## 確保 Git 修訂版本中的資訊清單真正不可變

使用 `helm` 或 `kustomize` 等範本工具時，資訊清單的含義可能會在一天之內發生變化。這通常是由對上游 helm 儲存庫或 kustomize 基礎所做的變更所引起的。

例如，考慮以下 kustomization.yaml

```yaml
resources:
- github.com/argoproj/argo-cd//manifests/cluster-install
```

上述 kustomization 有一個指向 argo-cd 儲存庫的 HEAD 修訂版本的遠端基礎。由於這不是一個穩定的目標，因此即使您自己的 Git 儲存庫沒有任何變更，此 kustomize 應用程式的資訊清單也可能突然改變含義。

更好的版本是使用 Git 標籤或提交 SHA。例如：

```yaml
bases:
- github.com/argoproj/argo-cd//manifests/cluster-install?ref=v0.11.1
```
