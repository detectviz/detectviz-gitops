# 選擇性同步

*選擇性同步*是指只同步部分資源。您可以從 UI 中選擇要同步的資源：

![選擇性同步](../assets/selective-sync.png)

執行此操作時，請記住：

* 您的同步不會記錄在歷史記錄中，因此無法回滾。
* 不會執行 [Hooks](resource_hooks.md)。

## 選擇性同步選項

開啟選擇性同步選項，它將只同步未同步的資源。
有關更多詳細資訊，請參閱[同步選項](sync-options.md#selective-sync) 文件。
