# Git 檔案產生器 Globbing

## 問題陳述

Git 檔案產生器的原始和預設實作執行非常貪婪的 globbing。這可能會觸發錯誤或讓使用者措手不及。例如，請考慮以下儲存庫佈局：

```
└── cluster-charts/
    ├── cluster1
    │   ├── mychart/
    │   │   ├── charts/
    │   │   │    └── mysubchart/
    │   │   │        ├── values.yaml
    │   │   │        └── etc…
    │   │   ├── values.yaml
    │   │   └── etc…
    │   └── myotherchart/
    │       ├── values.yaml
    │       └── etc…
    └── cluster2
        └── etc…
```

在 `cluster1` 中，我們有兩個圖表，其中一個帶有子圖表。

假設我們需要 ApplicationSet 在 `values.yaml` 中建立範本值，那麼我們需要使用 Git 檔案產生器而不是目錄產生器。Git 檔案產生器的 `path` 鍵的值應設定為：

```
path: cluster-charts/*/*/values.yaml
```

但是，預設實作會將上述模式解釋為：

```
path: cluster-charts/**/values.yaml
```

這意味著，對於 `cluster1` 中的 `mychart`，它將同時選取圖表的 `values.yaml` 以及其子圖表的 `values.yaml`。這很可能會失敗，即使沒有失敗也是錯誤的。

這種不希望的 globbing 可能會以多種其他方式失敗。例如：

```
path: some-path/*.yaml
```

這將傳回 `some-path` 下任何層級的任何目錄中的所有 YAML 檔案，而不僅僅是直接在它下面的那些。

## 啟用新的 Globbing

由於某些使用者可能依賴舊的行為，因此決定將修復設為可選，並且預設不啟用。

可以透過以下任何一種方式啟用它：

1. 將 `--enable-new-git-file-globbing` 傳遞給 ApplicationSet 控制器參數。
1. 在 ApplicationSet 控制器環境變數中設定 `ARGOCD_APPLICATIONSET_CONTROLLER_ENABLE_NEW_GIT_FILE_GLOBBING=true`。
1. 在 `argocd-cmd-params-cm` ConfigMap 中設定 `applicationsetcontroller.enable.new.git.file.globbing: "true"`。

請注意，預設值將來可能會變更。

## 用法

新的 Git 檔案產生器 globbing 使用 `doublestar` 套件。您可以在[此處](https://github.com/bmatcuk/doublestar)找到它。

以下是其文件的簡短摘錄。

doublestar 模式會遞迴地匹配檔案和目錄。例如，如果您有以下目錄結構：

```bash
grandparent
`-- parent
    |-- child1
    `-- child2
```

您可以使用 `**/child*`、
`grandparent/**/child?`、`**/parent/*`，甚至只是 `**` 本身（它將遞迴地傳回所有檔案和目錄）等模式來尋找子項。

Bash 的 globstar 是 doublestar 的靈感來源，因此，它們的運作方式類似。
請注意，doublestar 必須單獨作為路徑元件出現。像 `/path**` 這樣的模式是無效的，將被視為與 `/path*` 相同，但
`/path*/**` 應該可以達到預期的結果。此外，`/path/**` 將
匹配路徑目錄下的所有目錄和檔案，但 `/path/**/` 將
只匹配目錄。
