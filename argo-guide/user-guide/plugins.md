# 外掛程式

## 總覽

本指南將示範如何為
`argocd` CLI 工具撰寫外掛程式。外掛程式是一種使用新子指令擴充 `argocd` CLI 的方式，
允許使用不屬於 `argocd` CLI 預設發行版的自訂功能
。

如果您想查看原始提案，請前往此[增強提案](../proposals/argocd-cli-pluin.md)。
它涵蓋了外掛程式機制的運作方式、其優點、動機以及其旨在實現的目標。

## 先決條件

您需要在本地安裝一個可用的 `argocd` 二進位檔。您可以遵循
[cli 安裝文件](https://argo-cd.readthedocs.io/en/stable/cli_installation/)來安裝該二進位檔。

## 建立 `argocd` 外掛程式

外掛程式是一個獨立的可執行檔，其名稱以 argocd- 開頭。
若要安裝外掛程式，請將其可執行檔移至 PATH 中包含的任何目錄。
請確保 PATH 組態指定了可執行檔的完整絕對路徑，
而不是相對路徑。`argocd` 允許外掛程式新增自訂指令，例如
`argocd my-plugin arg1 arg2 --flag1`，方法是在 PATH 中執行 `argocd-my-plugin` 二進位檔。

## 限制

1. 目前無法建立覆寫現有
`argocd` 指令的外掛程式。例如，建立一個名為 `argocd-version`
的外掛程式會導致該外掛程式永遠不會被執行，因為現有的 `argocd version`
指令將始終優先於它。由於此限制，
也無法使用外掛程式將新的子指令新增至現有的 `argocd` 指令。
例如，透過將您的外掛程式命名為
`argocd-cluster` 來新增子指令 `argocd cluster upgrade` 會導致該外掛程式被忽略。

2. 目前無法剖析 `argocd` CLI 設定的全域旗標。例如，
如果您已將任何全域旗標值（例如 `--logformat` 值）設定為 `text`，則外掛程式將
不會剖析全域旗標，並將預設值傳遞給 `--logformat` 旗標，即 `json`。
對於現有的 `argocd` 指令，旗標剖析的運作方式完全相同，這表示執行
現有的 argocd 指令（例如 `argocd cluster list`）將會正確地將旗標值剖析為 `text`。

## `argocd` 外掛程式的條件

您希望作為 `argocd` 外掛程式執行的任何二進位檔都需要滿足以下三個條件：

1. 二進位檔應以 `argocd-` 作為前綴名稱。例如，
   `argocd-demo-plugin` 或 `argocd-demo_plugin` 是有效的二進位檔名稱，但
   `argocd_demo-plugin` 或 `argocd_demo_plugin` 則不是。
2. 二進位檔應具有可執行權限，否則將被忽略。
3. 二進位檔應位於系統的絕對 PATH 中的任何位置。

## 撰寫 `argocd` 外掛程式

### 命名外掛程式

Argo CD 外掛程式的檔名必須以 `argocd-` 開頭。外掛程式實作的子指令
由檔名中 `argocd-` 前綴之後的部分決定。
`argocd-` 之後的任何內容都將成為 `argocd` 的子指令。

例如，一個名為 `argocd-demo-plugin` 的外掛程式在使用者輸入時會被叫用：
```bash
argocd demo-plugin [args] [flags]
```

`argocd` CLI 會根據提供的子指令來決定要叫用哪個外掛程式。

例如，執行以下指令：
```bash
argocd my-custom-command [args] [flags]
```
如果 PATH 中存在名為 `argocd-my-custom-command` 的外掛程式，則會導致其執行。

### 撰寫外掛程式

外掛程式可以用任何程式語言或腳本撰寫，只要它允許您撰寫命令列指令即可。

外掛程式會根據其名稱來決定它希望實作哪個指令路徑。

例如，如果您的系統絕對 PATH 中有一個名為 `argocd-demo-plugin` 的二進位檔，而使用者執行以下指令：

```bash
argocd demo-plugin subcommand1 --flag=true
```

Argo CD 會將其轉譯並執行對應的外掛程式，指令如下：

```bash
argocd-demo-plugin subcommand1 --flag=true
```

同樣地，如果在絕對 PATH 中找到一個名為 `argocd-demo-demo-plugin` 的外掛程式，而使用者叫用：

```bash
argocd demo-demo-plugin subcommand2 subcommand3 --flag=true
```

Argo CD 將執行外掛程式為：

```bash
argocd-demo-demo-plugin subcommand2 subcommand3 --flag=true
```

### 範例外掛程式
```bash
#!/bin/bash

# 檢查 argocd CLI 是否已安裝
if ! command -v argocd &> /dev/null; then
    echo "錯誤：Argo CD CLI (argocd) 尚未安裝。請先安裝它。"
    exit 1
fi

if [[ "$1" == "version" ]]
then
    echo "正在顯示 argocd 版本..."
    argocd version
    exit 0
fi


echo "我是一個名為 argocd-foo 的外掛程式"
```

### 使用外掛程式

若要使用外掛程式，請將外掛程式設為可執行：
```bash
sudo chmod +x ./argocd-foo
```

並將其放置在您的 `PATH` 中的任何位置：
```bash
sudo mv ./argocd-foo /usr/local/bin
```

您現在可以將您的外掛程式作為 argocd 指令叫用：
```bash
argocd foo
```

這將產生以下輸出
```bash
我是一個名為 argocd-foo 的外掛程式
```

所有引數和旗標都會原封不動地傳遞給可執行檔：
```bash
argocd foo version
```

這將產生以下輸出
```bash
DEBU[0000] 指令不存在，正在尋找外掛程式...
正在顯示 argocd 版本...
2025/01/16 13:24:36 maxprocs: 離開 GOMAXPROCS=16：CPU 配額未定義
argocd: v2.13.0-rc2+0f083c9
  BuildDate: 2024-09-20T11:59:25Z
  GitCommit: 0f083c9e58638fc292cf064e294a1aa53caa5630
  GitTreeState: clean
  GoVersion: go1.22.7
  Compiler: gc
  Platform: linux/amd64
argocd-server: v2.13.0-rc2+0f083c9
  BuildDate: 2024-09-20T11:59:25Z
  GitCommit: 0f083c9e58638fc292cf064e294a1aa53caa5630
  GitTreeState: clean
  GoVersion: go1.22.7
  Compiler: gc
  Platform: linux/amd64
  Kustomize Version: v5.4.3 2024-07-19T16:40:33Z
  Helm Version: v3.15.2+g1a500d5
  Kubectl Version: v0.31.0
  Jsonnet Version: v0.20.0
```

## 分發 `argocd` 外掛程式

如果您已開發了一個供他人使用的 Argo CD 外掛程式，
您應仔細考慮如何打包、分發和
交付更新，以確保您的使用者能有順暢的安裝和升級過程
。

### 原生/特定平台的套件管理

您可以使用傳統的套件管理器來分發您的外掛程式，
例如 Linux 的 `apt` 或 `yum`、Windows 的 `Chocolatey` 和 macOS 的 `Homebrew`。
這些套件管理器非常適合分發外掛程式，因為它們可以
將可執行檔直接放置在使用者的 PATH 中，使其易於存取。

然而，作為外掛程式作者，選擇這種方法也伴隨著
維護和更新每個版本在多個平台上的外掛程式分發套件的責任
。這包括相容性測試、確保及時更新
以及管理版本控制，以便為您的使用者提供無縫的體驗。

### 原始碼

您可以發布外掛程式的原始碼，例如，
在 Git 儲存庫中。這讓使用者可以直接存取和檢查
程式碼。想要安裝外掛程式的使用者將需要
取得程式碼、設定合適的建置環境（如果外掛程式需要編譯），
並手動部署它。
