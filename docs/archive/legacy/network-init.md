
### 🎯 結論：問題 100% 在 `rp_filter`

根據你的 `sysctl` 輸出，真正的**問題點**是 **(1) `rp_filter`**。

你可能會感到困惑，因為 Proxmox Host 上的 `net.ipv4.conf.tap111i0.rp_filter` 明明顯示為 `0` (關閉)。

**這就是陷阱所在。**

-----

### 💡 深入分析：`all` 與 `tap` 的 `rp_filter`

Linux 核心在決定 `rp_filter` 是否生效時，其採用的**有效值 (Effective Value)** 並不只是看單一介面的設定，而是：

**`有效值 = max(net.ipv4.conf.all.rp_filter, net.ipv4.conf.IFACE.rp_filter)`**

讓我們套用你 Proxmox Host 上的數據：

  * `net.ipv4.conf.all.rp_filter = 2` (嚴格模式)
  * `net.ipv4.conf.tap111i0.rp_filter = 0` (關閉)

因此，`tap111i0` 介面實際生效的 `rp_filter` 設定是：
`max(2, 0) = 2`

這表示 `tap111i0` 介面**實際上是處於嚴格模式 (Strict Mode)**。

這完美解釋了你的抓包結果：

1.  ICMP Reply 封包 (來源 IP: 網關) 到達 `vmbr0`。
2.  `vmbr0` 橋接器將它轉發到 `tap111i0`。
3.  `tap111i0` 介面收到封包，觸發 `rp_filter` 檢查。
4.  核心檢查：「如果我要回封包給『網關 IP』，我會從 `tap111i0` 送出去嗎？」
5.  答案：「不會，我會從 `vmbr0` 送出去。」
6.  **`rp_filter = 2` 檢查失敗，封包被核心安靜地丟棄。**
7.  封包從未到達 VM 內部。

-----

### 逐一排除其他原因

你的數據同時也幫我們**明確排除**了其他三個可能性：

#### 2. 防火牆 (結論：已排除)

  * **Proxmox Host:** `iptables -L -n` 顯示 `policy ACCEPT` 且沒有任何規則。 (已排除)
  * **Proxmox VM:** `qm config` 顯示 `firewall=0`。 (已排除)
  * **Ubuntu VM:** `ufw status verbose` 顯示 `Status: inactive`。 (已排除)

#### 3. MTU 設定 (結論：已排除)

  * **Proxmox Host:** `vmbr0` (1500), `tap111i0` (1500)。
  * **Ubuntu VM:** `eth0` (1500)。
  * 所有相關介面的 MTU 都是 `1500`，完全一致。 (已排除)

#### 4. TAP 轉發行為 (結論：已排除)

  * `qm config` 顯示 `agent: enabled=1` (Guest Agent 已開啟)。
  * `ip link show` 顯示 `tap111i0` 介面已經是 `PROMISC` (混雜模式) 狀態。
  * `qm config` 的 `net0` 沒有 `tag=` 參數，表示沒有 VLAN 標籤問題。
  * (已排除)

-----

### 💻 修正程式碼 (在 Proxmox Host 上)

你**必須**修改 **Proxmox Host (宿主機)** 的 `sysctl` 設定，而不是 VM。

1.  **建立 (或修改) PVE Host 上的設定檔：**

    ```bash
    nano /etc/sysctl.d/98-pve-networking.conf
    ```

2.  **貼上以下內容：**

    ```ini
    # 解決 KVM/Bridge/Tap 網路封包遺失問題
    # 將 rp_filter 設為 1 (Loose Mode) 而不是 0 (Off)
    # 這會同時覆蓋 'all' 和 'default' 的設定

    net.ipv4.conf.all.rp_filter = 1
    net.ipv4.conf.default.rp_filter = 1
    ```

    > **說明：** 設為 `1` (寬鬆模式) 是 KVM/Bridge 環境的最佳實踐，它兼顧了安全與相容性。設為 `0` (關閉) 也可以，但安全性較低。

3.  **立即載入設定：**

    ```bash
    # 載入所有 .conf 檔案，包含你剛才建立的
    sysctl --system
    ```

4.  **驗證：**
    重新執行 `sysctl -a | grep 'net.ipv4.conf.*.rp_filter'`，你應該會看到 `net.ipv4.conf.all.rp_filter` 已經變成 `1`。