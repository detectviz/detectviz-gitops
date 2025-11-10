# DNS 伺服器設置指南

## 概述

本指南說明如何在 Proxmox 主機上設置 dnsmasq 作為內部 DNS 伺服器，為 DetectViz 集群提供域名解析服務。

## DNS 架構

### 服務範圍
- **內部域名**：`detectviz.internal` 區域
- **外部域名**：轉發到上游 DNS (8.8.8.8, 1.1.1.1)
- **服務對象**：Proxmox 主機、所有 VM、集群節點

### 網路範圍
- **管理網路**：192.168.0.0/24
- **集群網路**：10.244.0.0/16 (Pod CIDR)
- **服務網路**：10.96.0.0/12 (Service CIDR)

## 安裝和配置

### 1. 安裝 dnsmasq
```bash
apt update
apt install dnsmasq -y
```

### 2. 建立配置檔案
```bash
# 編輯 dnsmasq 配置
vim /etc/dnsmasq.d/detectviz.conf
```

### 3. 配置內容
```ini
# Detectviz internal DNS zone
domain=detectviz.internal
expand-hosts
local=/detectviz.internal/

# 主機記錄
address=/proxmox.detectviz.internal/192.168.0.2
address=/k8s-api.detectviz.internal/192.168.0.10
address=/master-1.detectviz.internal/192.168.0.11
address=/master-2.detectviz.internal/192.168.0.12
address=/master-3.detectviz.internal/192.168.0.13
address=/app-worker.detectviz.internal/192.168.0.14

# 應用服務域名
address=/argocd.detectviz.local/192.168.0.10      # ArgoCD UI (指向運行 NGINX 的節點)

# 上游 DNS
server=8.8.8.8
server=1.1.1.1

# 開放 LAN 範圍查詢
listen-address=127.0.0.1,192.168.0.2
bind-interfaces
```

### 4. 啟動服務
```bash
systemctl enable --now dnsmasq
systemctl restart dnsmasq
systemctl status dnsmasq
```

## 域名映射表

| 域名 | IP 位址 | 用途 |
|------|---------|------|
| `proxmox.detectviz.internal` | 192.168.0.2 | Proxmox Web UI |
| `k8s-api.detectviz.internal` | 192.168.0.10 | Kubernetes API VIP |
| `master-1.detectviz.internal` | 192.168.0.11 | Master 節點 #1 |
| `master-2.detectviz.internal` | 192.168.0.12 | Master 節點 #2 |
| `master-3.detectviz.internal` | 192.168.0.13 | Master 節點 #3 |
| `app-worker.detectviz.internal` | 192.168.0.14 | Application Worker |
| `argocd.detectviz.local` | 192.168.0.10 | ArgoCD UI |

## 本機 DNS 設定

本機加入 `/etc/hosts` 檔案，方便使用者使用域名連線到各個節點。

```bash
192.168.0.2 proxmox.detectviz.internal proxmox
192.168.0.10 k8s-api.detectviz.internal k8s-api
192.168.0.11 master-1.detectviz.internal master-1
192.168.0.12 master-2.detectviz.internal master-2
192.168.0.13 master-3.detectviz.internal master-3
192.168.0.14 app-worker.detectviz.internal app-worker
192.168.0.104 ipmi.detectviz.internal ipmi
```

## 測試和驗證

### 基本測試
```bash
# 測試內部域名解析
dig master-1.detectviz.internal @127.0.0.1
dig app-worker.detectviz.internal @192.168.0.2
dig argocd.detectviz.local @192.168.0.2

# 測試外部域名解析
dig google.com @192.168.0.2
```

### 批量測試
```bash
# 測試所有集群節點
for host in proxmox k8s-api master-1 master-2 master-3 app-worker; do
  echo "Testing $host.detectviz.internal:"
  dig $host.detectviz.internal @192.168.0.2 +short
  echo
done
```

## 集群節點配置

### 更新 resolv.conf
在所有集群節點上配置 DNS：

```bash
# 編輯 resolv.conf
nano /etc/resolv.conf

# 配置內容
nameserver 192.168.0.2
search detectviz.internal
```

### Ansible 自動化配置
```yaml
---
- name: Configure internal DNS for Detectviz
  hosts: all
  become: yes
  tasks:
    - name: Update resolv.conf
      copy:
        dest: /etc/resolv.conf
        content: |
          nameserver 192.168.0.2
          search detectviz.internal
```

## 維護和故障排除

### 服務管理
```bash
# 檢查服務狀態
systemctl status dnsmasq

# 查看日誌
journalctl -u dnsmasq

# 重新載入配置
systemctl reload dnsmasq
```

### 常見問題

#### DNS 解析失敗
```bash
# 檢查配置語法
dnsmasq --test

# 檢查網路連線
ping 8.8.8.8

# 檢查防火牆
iptables -L | grep 53
```

#### 域名未解析
- 檢查配置檔案語法
- 確認域名格式正確
- 檢查 dnsmasq 服務狀態
- 驗證網路連線

#### 外部域名解析問題
- 檢查上游 DNS 服務器
- 確認網路連線正常
- 查看 dnsmasq 日誌錯誤

### 進階故障排除
```bash
# 詳細日誌
dnsmasq -d -q

# 檢查 DNS 查詢
dig @192.168.0.2 detectviz.internal

# 網路抓包分析
tcpdump -i any port 53
```

## 安全注意事項

### 訪問控制
- 限制 DNS 服務器訪問範圍
- 監控 DNS 查詢日誌
- 定期檢查配置安全

### 配置備份
```bash
# 備份 DNS 配置
cp /etc/dnsmasq.d/detectviz.conf /etc/dnsmasq.d/detectviz.conf.backup

# 備份 resolv.conf 配置
cp /etc/resolv.conf /etc/resolv.conf.backup
```

## 相關文檔

- [Bridge 配置指南](bridge-config.md)
- [網路優化指南](network-optimization.md)
- [域名映射](domain-mapping.md)
- [Proxmox 配置指南](../proxmox/configuration.md)
