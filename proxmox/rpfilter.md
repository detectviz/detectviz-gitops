# rp_filter 設定

解決 KVM/Bridge/Tap 網路封包遺失問題，將 `rp_filter` 設為 `1` (Loose Mode) 而不是 `0` (Off)，這會同時覆蓋 `all` 和 `default` 的設定。

-----

## 步驟 1：建立新的設定檔

請在 Proxmox Host 的 shell 中執行以下指令。我們將建立一個名為 `98-pve-networking.conf` 的檔案：

(使用 `cat` 配合 `tee` 是一種很方便的寫入檔案的方式)

```bash
cat << EOF | sudo tee /etc/sysctl.d/98-pve-networking.conf
# 修正 Proxmox KVM/Bridge/Tap 網路封包遺失 (ICMP Reply)
# 將 rp_filter 設為 1 (Loose Mode) 以允許橋接的非對稱路由
# 這是解決 ICMP 封包被 tap 介面丟棄的關鍵
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
EOF
```

## 步驟 2：立即載入設定

建立檔案後，你需要讓核心立即重新讀取所有 `/etc/sysctl.d/` 下的設定：

```bash
sudo sysctl --system
```

> **說明：** 這個指令會重新載入所有 `.conf` 檔案，包含你剛剛建立的 `98-pve-networking.conf`。

## 步驟 3：驗證

現在，再次檢查 `all.rp_filter` 的值：

```bash
sysctl net.ipv4.conf.all.rp_filter
```

**預期輸出：**
`net.ipv4.conf.all.rp_filter = 1`

-----

# 總結

完成上述步驟後，`all.rp_filter` 就會被正確設定為 `1` (寬鬆模式)。這將使 `tap111i0` 介面的**有效值**變為 `max(1, 0) = 1`，封包就不會再被丟棄了。
