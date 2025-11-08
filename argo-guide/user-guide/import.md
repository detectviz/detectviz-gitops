# 匯入 Argo CD go 套件

## 問題

在您自己的專案中匯入 Argo CD 套件時，下載相依性時可能會遇到一些錯誤，例如「unknown revision v0.0.0」。這是因為 Argo CD 直接依賴於一些 Kubernetes 套件，這些套件的 go.mod 中有這些未知的 v0.0.0 版本。

## 解決方案

在您自己的 go.mod 中新增一個 replace 區段，與對應的 Argo CD 版本的 go.mod 中的 replace 區段相同。為了找到特定版本的 go.mod，請導覽至 [Argo CD 儲存庫](https://github.com/argoproj/argo-cd/) 並按一下切換分支/標籤下拉式選單以選取您要尋找的版本。現在您可以檢視特定版本的 go.mod 檔案以及所有其他檔案。

## 範例

如果您正在使用 Argo CD v2.4.15，您的 go.mod 應該包含以下內容：

```
replace (
    // https://github.com/golang/go/issues/33546#issuecomment-519656923
    github.com/go-check/check => github.com/go-check/check v0.0.0-20180628173108-788fd7840127

    github.com/golang/protobuf => github.com/golang/protobuf v1.4.2
    github.com/gorilla/websocket => github.com/gorilla/websocket v1.4.2
    github.com/grpc-ecosystem/grpc-gateway => github.com/grpc-ecosystem/grpc-gateway v1.16.0
    github.com/improbable-eng/grpc-web => github.com/improbable-eng/grpc-web v0.0.0-20181111100011-16092bd1d58a

    // 避免 CVE-2022-28948
    gopkg.in/yaml.v3 => gopkg.in/yaml.v3 v3.0.1

    // https://github.com/kubernetes/kubernetes/issues/79384#issuecomment-505627280
    k8s.io/api => k8s.io/api v0.23.1
    k8s.io/apiextensions-apiserver => k8s.io/apiextensions-apiserver v0.23.1
    k8s.io/apimachinery => k8s.io/apimachinery v0.23.1
    k8s.io/apiserver => k8s.io/apiserver v0.23.1
    k8s.io/cli-runtime => k8s.io/cli-runtime v0.23.1
    k8s.io/client-go => k8s.io/client-go v0.23.1
    k8s.io/cloud-provider => k8s.io/cloud-provider v0.23.1
    k8s.io/cluster-bootstrap => k8s.io/cluster-bootstrap v0.23.1
    k8s.io/code-generator => k8s.io/code-generator v0.23.1
    k8s.io/component-base => k8s.io/component-base v0.23.1
    k8s.io/component-helpers => k8s.io/component-helpers v0.23.1
    k8s.io/controller-manager => k8s.io/controller-manager v0.23.1
    k8s.io/cri-api => k8s.io/cri-api v0.23.1
    k8s.io/csi-translation-lib => k8s.io/csi-translation-lib v0.23.1
    k8s.io/kube-aggregator => k8s.io/kube-aggregator v0.23.1
    k8s.io/kube-controller-manager => k8s.io/kube-controller-manager v0.23.1
    k8s.io/kube-proxy => k8s.io/kube-proxy v0.23.1
    k8s.io/kube-scheduler => k8s.io/kube-scheduler v0.23.1
    k8s.io/kubectl => k8s.io/kubectl v0.23.1
    k8s.io/kubelet => k8s.io/kubelet v0.23.1
    k8s.io/legacy-cloud-providers => k8s.io/legacy-cloud-providers v0.23.1
    k8s.io/metrics => k8s.io/metrics v0.23.1
    k8s.io/mount-utils => k8s.io/mount-utils v0.23.1
    k8s.io/pod-security-admission => k8s.io/pod-security-admission v0.23.1
    k8s.io/sample-apiserver => k8s.io/sample-apiserver v0.23.1
)
```
