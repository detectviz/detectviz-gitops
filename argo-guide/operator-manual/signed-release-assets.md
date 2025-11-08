# Argo CD 成品的驗證

## 先決條件
- cosign `v2.0.0` 或更高版本 [安裝說明](https://docs.sigstore.dev/cosign/installation)
- slsa-verifier [安裝說明](https://github.com/slsa-framework/slsa-verifier#installation)
- crane [安裝說明](https://github.com/google/go-containerregistry/blob/main/cmd/crane/README.md)（僅用於容器驗證）

***
## 發行資產
| 資產 | 說明 |
|---|---|
| argocd-darwin-amd64 | CLI 二進位檔 |
| argocd-darwin-arm64 | CLI 二進位檔 |
| argocd-linux_amd64 | CLI 二進位檔 |
| argocd-linux_arm64 | CLI 二進位檔 |
| argocd-linux_ppc64le | CLI 二進位檔 |
| argocd-linux_s390x | CLI 二進位檔 |
| argocd-windows_amd64 | CLI 二進位檔 |
| argocd-cli.intoto.jsonl | CLI 二進位檔的證明 |
| argocd-sbom.intoto.jsonl | SBOM 的證明 |
| cli_checksums.txt | 二進位檔的校驗和 |
| sbom.tar.gz | Sbom |
| sbom.tar.gz.pem | 用於簽署 sbom 的憑證 |
| sbom.tar.gz.sig | sbom 的簽章 |

***
## 容器映像檔的驗證

Argo CD 容器映像檔是使用基於身分的（「無金鑰」）簽署和透明度由 [cosign](https://github.com/sigstore/cosign) 簽署的。執行以下指令可用於驗證容器映像檔的簽章：

```bash
cosign verify \
--certificate-identity-regexp https://github.com/argoproj/argo-cd/.github/workflows/image-reuse.yaml@refs/tags/v \
--certificate-oidc-issuer https://token.actions.githubusercontent.com \
--certificate-github-workflow-repository "argoproj/argo-cd" \
quay.io/argoproj/argocd:v2.11.3 | jq
```
如果容器映像檔已正確驗證，指令應輸出以下內容：
```bash
The following checks were performed on each of these signatures:
  - The cosign claims were validated
  - Existence of the claims in the transparency log was verified offline
  - Any certificates were verified against the Fulcio roots.
[
  {
    "critical": {
      "identity": {
        "docker-reference": "quay.io/argoproj/argo-cd"
      },
      "image": {
        "docker-manifest-digest": "sha256:63dc60481b1b2abf271e1f2b866be8a92962b0e53aaa728902caa8ac8d235277"
      },
      "type": "cosign container image signature"
    },
    "optional": {
      "1.3.6.1.4.1.57264.1.1": "https://token.actions.githubusercontent.com",
      "1.3.6.1.4.1.57264.1.2": "push",
      "1.3.6.1.4.1.57264.1.3": "a6ec84da0eaa519cbd91a8f016cf4050c03323b2",
      "1.3.6.1.4.1.57264.1.4": "Publish ArgoCD Release",
      "1.3.6.1.4.1.57264.1.5": "argoproj/argo-cd",
      "1.3.6.1.4.1.57264.1.6": "refs/tags/<version>",
      ...
```

***
## 使用 SLSA 證明驗證容器映像檔

使用 [slsa-github-generator](https://github.com/slsa-framework/slsa-github-generator) 產生 [SLSA](https://slsa.dev/) Level 3 來源證明。

以下指令將驗證證明的簽章以及其發行方式。它將包含 payloadType、payload 和簽章。

根據 [slsa-verifier 文件](https://github.com/slsa-framework/slsa-verifier/tree/main#containers)執行以下指令：

```bash
# 取得不可變的容器映像檔以防止 TOCTOU 攻擊 https://github.com/slsa-framework/slsa-verifier#toctou-attacks
IMAGE=quay.io/argoproj/argocd:v2.7.0
IMAGE="${IMAGE}@"$(crane digest "${IMAGE}")
# 驗證來源證明，包括標籤以防止回滾攻擊。
slsa-verifier verify-image "$IMAGE" \
    --source-uri github.com/argoproj/argo-cd \
    --source-tag v2.7.0
```

如果您只想驗證來源儲存庫標籤的主要或次要版本（而不是完整標籤），請使用 `--source-versioned-tag`，它會執行語意版本驗證：

```shell
slsa-verifier verify-image "$IMAGE" \
    --source-uri github.com/argoproj/argo-cd \
    --source-versioned-tag v2 # 注意：可使用 v2.7 進行次要版本驗證。
```

證明負載包含一個不可偽造的來源證明，該證明是 base64 編碼的，可以透過將 `--print-provenance` 選項傳遞給上述指令來檢視：

```bash
slsa-verifier verify-image "$IMAGE" \
    --source-uri github.com/argoproj/argo-cd \
    --source-tag v2.7.0 \
    --print-provenance | jq
```

如果您偏好使用 cosign，請遵循這些[說明](https://github.com/slsa-framework/slsa-github-generator/blob/main/internal/builders/container/README.md#cosign)。

> [!TIP]
> `cosign` 或 `slsa-verifier` 都可用於驗證映像檔證明。
> 有關詳細說明，請查看每個二進位檔的文件。

***

## 使用 SLSA 證明驗證 CLI 成品

每個發行版本都提供單一證明（`argocd-cli.intoto.jsonl`）。這可以與 [slsa-verifier](https://github.com/slsa-framework/slsa-verifier#verification-for-github-builders) 一起使用，以驗證 CLI 二進位檔是使用 GitHub 上的 Argo CD 工作流程產生的，並確保其經過密碼學簽署。

```bash
slsa-verifier verify-artifact argocd-linux-amd64 \
  --provenance-path argocd-cli.intoto.jsonl \
  --source-uri github.com/argoproj/argo-cd \
  --source-tag v2.7.0
```

如果您只想驗證來源儲存庫標籤的主要或次要版本（而不是完整標籤），請使用 `--source-versioned-tag`，它會執行語意版本驗證：

```shell
slsa-verifier verify-artifact argocd-linux-amd64 \
  --provenance-path argocd-cli.intoto.jsonl \
  --source-uri github.com/argoproj/argo-cd \
  --source-versioned-tag v2 # 注意：可使用 v2.7 進行次要版本驗證。
```

負載是一個不可偽造的來源證明，它是 base64 編碼的，可以透過將 `--print-provenance` 選項傳遞給上述指令來檢視：

```bash
slsa-verifier verify-artifact argocd-linux-amd64 \
  --provenance-path argocd-cli.intoto.jsonl \
  --source-uri github.com/argoproj/argo-cd \
  --source-tag v2.7.0 \
  --print-provenance | jq
```

## Sbom 的驗證

每個發行版本都提供單一證明（`argocd-sbom.intoto.jsonl`）以及 sbom（`sbom.tar.gz`）。這可以與 [slsa-verifier](https://github.com/slsa-framework/slsa-verifier#verification-for-github-builders) 一起使用，以驗證 SBOM 是使用 GitHub 上的 Argo CD 工作流程產生的，並確保其經過密碼學簽署。

```bash
slsa-verifier verify-artifact sbom.tar.gz \
  --provenance-path argocd-sbom.intoto.jsonl \
  --source-uri github.com/argoproj/argo-cd \
  --source-tag v2.7.0
```

***
## Kubernetes 上的驗證

### 策略控制器
> [!NOTE]
> 我們鼓勵所有使用者使用您選擇的准入/策略控制器來驗證簽章和來源證明。這樣做將在映像檔部署到您的 Kubernetes 叢集之前驗證它是由我們建置的。

Cosign 簽章和 SLSA 來源證明與多種類型的准入控制器相容。請參閱 [cosign 文件](https://docs.sigstore.dev/cosign/overview/#kubernetes-integrations)和 [slsa-github-generator](https://github.com/slsa-framework/slsa-github-generator/blob/main/internal/builders/container/README.md#verification) 以取得支援的控制器。
