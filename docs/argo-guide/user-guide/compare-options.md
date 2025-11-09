# 比較選項

## 忽略多餘的資源

在某些情況下，您可能希望將某些資源從應用程式的整體同步狀態中排除，例如，如果它們是由工具產生的。您可以透過在您希望排除的資源上新增此註釋來達成此目的：

```yaml
metadata:
  annotations:
    argocd.argoproj.io/compare-options: IgnoreExtraneous
```

![比較選項需要刪減](../assets/compare-option-ignore-needs-pruning.png)

> [!NOTE]
> 這只會影響同步狀態。如果資源的健康狀況不佳，那麼應用程式也會處於不佳狀態。

Kustomize 有一個功能可以讓您產生 config map ([閱讀更多 ⧉](https://github.com/kubernetes-sigs/kustomize/blob/master/examples/configGeneration.md))。您可以設定 `generatorOptions` 來新增此註釋，以便您的應用程式保持同步：

```yaml
configMapGenerator:
  - name: my-map
    literals:
      - foo=bar
generatorOptions:
  annotations:
    argocd.argoproj.io/compare-options: IgnoreExtraneous
kind: Kustomization
``` 
 
> [!NOTE]
> `generatorOptions` 會同時在 config map 和 secret 上新增註釋 ([閱讀更多 ⧉](https://github.com/kubernetes-sigs/kustomize/blob/master/examples/generatorOptions.md))。
> 
您可能希望將此與 [`Prune=false` 同步選項](sync-options.md)結合使用。
