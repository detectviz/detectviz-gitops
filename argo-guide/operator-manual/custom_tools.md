# 自訂工具

Argo CD 在其容器映像檔中捆綁了其支援的樣板工具（helm、kustomize、ks、jsonnet）的偏好版本。有時，可能需要使用 Argo CD 捆綁版本以外的特定工具版本。這樣做的原因可能包括：

* 由於錯誤或錯誤修復，需要升級/降級到特定版本的工具。
* 安裝額外的相依性，以供 kustomize 的 configmap/secret 產生器使用。
  （例如 curl、vault、gpg、AWS CLI）
* 安裝[組態管理外掛程式](config-management-plugins.md)。

由於 Argo CD repo-server 是負責產生 Kubernetes 清單的單一服務，因此可以對其進行自訂，以使用您環境所需的替代工具鏈。

## 透過磁碟區掛載新增工具

第一種技術是使用 `init` 容器和 `volumeMount` 將不同版本的工具複製到 repo-server 容器中。在以下範例中，一個 init 容器正在用與 Argo CD 捆綁版本不同的版本覆寫 helm 二進位檔案：

```yaml
    spec:
      # 1. 定義一個 emptyDir 磁碟區，用於存放自訂二進位檔案
      volumes:
      - name: custom-tools
        emptyDir: {}
      # 2. 使用 init 容器將自訂二進位檔案下載/複製到 emptyDir 中
      initContainers:
      - name: download-tools
        image: alpine:3.8
        command: [sh, -c]
        args:
        - wget -qO- https://get.helm.sh/helm-v2.12.3-linux-amd64.tar.gz | tar -xvzf - &&
          mv linux-amd64/helm /custom-tools/
        volumeMounts:
        - mountPath: /custom-tools
          name: custom-tools
      # 3. 將自訂二進位檔案磁碟區掛載到 bin 目錄（覆寫現有版本）
      containers:
      - name: argocd-repo-server
        volumeMounts:
        - mountPath: /usr/local/bin/helm
          name: custom-tools
          subPath: helm
```

## BYOI (建立您自己的映像檔)

有時更換二進位檔案是不夠的，您需要安裝其他相依性。以下範例從 Dockerfile 建置一個完全自訂的 repo-server，安裝產生清單可能需要的額外相依性。

```Dockerfile
FROM argoproj/argocd:v2.5.4 # 將標籤替換為適當的 argo 版本

# 切換到 root 以便能夠執行安裝
USER root

# 安裝您的 repo-server 檢索和解密密碼、呈現清單所需的工具
# (例如 curl、awscli、gpg、sops)
RUN apt-get update && \
    apt-get install -y \
        curl \
        awscli \
        gpg && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* && \
    curl -o /usr/local/bin/sops -L https://github.com/mozilla/sops/releases/download/3.2.0/sops-3.2.0.linux && \
    chmod +x /usr/local/bin/sops

# 切換回非 root 使用者
USER $ARGOCD_USER_ID
```
