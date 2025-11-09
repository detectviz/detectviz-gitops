# Jsonnet

目錄應用程式中任何符合 `*.jsonnet` 的檔案都會被視為 Jsonnet 檔案。Argo CD 會評估 Jsonnet 並能夠剖析產生的物件或陣列。

## 建置環境

Jsonnet 應用程式可以透過替換成 *TLAs* 和*外部變數*來存取[標準建置環境](build-environment.md)。
也可以相對於儲存庫根目錄新增一個共用函式庫（例如 `vendor` 資料夾）。

例如，透過 CLI：

```bash
argocd app create APPNAME \
  --jsonnet-ext-var-str 'app=${ARGOCD_APP_NAME}' \
  --jsonnet-tla-str 'ns=${ARGOCD_APP_NAMESPACE}' \
  --jsonnet-libs 'vendor'
```

或透過宣告式語法：

```yaml
  directory:
    jsonnet:
      extVars:
      - name: app
        value: $ARGOCD_APP_NAME
      tlas:
        - name: ns
          value: $ARGOCD_APP_NAMESPACE
      libs:
        - vendor
```
