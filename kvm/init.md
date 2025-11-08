# KVM (ASMB10-iKVM) 設置

## 一般設置
1. 日期 & 時間：勾選「NTP 自動更新日期 & 時間」，確保事件紀錄、日誌時間與主系統一致。
2. 網路設定：已設定 IPv4 靜態（192.168.0.104）並關閉 IPv6。
3. 使用者管理：建立第二組管理帳號（例如 `opsadmin`）。
4. KVM 滑鼠設置：若要用遠端控制安裝 Proxmox，設定為「相對位置模式 (Linux)」。
5. SSL 設定：可先保留內建憑證，若後續掛 `detectviz.com` 可匯入自簽憑證。

## 系統防火牆
IP 指向防火牆規則：`192.168.0.1` - `192.168.0.254`。
埠號防火牆規則：開啟，僅允許 `22` (SSH) / `443` (HTTPS) / `5900` (KVM) / `623` (IPMI)。

## DNS 配置
主機名稱設置：`ipmi`。
網域名稱：`detectviz.internal`。
DNS 伺服器 1：`192.168.0.1` 
DNS 伺服器 2：`8.8.8.8`。

## 網路設定
- IPv4 位址：`192.168.0.104`
- IPv4 子網：`255.255.255.0`
- IPv4 閘道：`192.168.0.1`

> 取消「啟用 IPv4 DHCP」勾選，確保隨時透過 https://192.168.0.104 管理 KVM。
> 關閉 IPv6 功能。
> 不要設定 VLAN（除非有多網段需求）。

## BIOS 設置
Other OS：`OS Type`
Secure Boot Mode：`Custom`
Boot Option Priorities：`proxmox` -> `UEFI OS` -> `UEFI: AMI Virtual CDROM0 1.00 Partition 1`

## 硬體規格
- 處理器：Intel(R) Core(TM) i7-14700F, 20 Core(s), 28 Logical Processors(s)
- 記憶體：D5-6000-32GB * 2
- 硬碟：TEAM TM8FPW002T 2048GB (NVMe) + Acer SSD RE100 2.5 512GB (SATA)
- 網卡：Intel I210-AT