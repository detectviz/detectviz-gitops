# 域名映射參考

## 概述

本文件說明 DetectViz 集群的域名映射配置，作為網路規劃和 DNS 配置的參考。

## 網路架構

### IP 分配總覽
| 角色 | 主機名稱 | IP 位址 | 用途 |
|------|----------|---------|------|
| Proxmox | proxmox | 192.168.0.2 | 虛擬化平台管理 |
| IPMI | ipmi | 192.168.0.104 | 硬體管理介面 |
| K8s VIP | k8s-api | 192.168.0.10 | Kubernetes API 負載均衡 |
| Master-1 | master-1 | 192.168.0.11 | 控制平面節點 #1 |
| Master-2 | master-2 | 192.168.0.12 | 控制平面節點 #2 |
| Master-3 | master-3 | 192.168.0.13 | 控制平面節點 #3 |
| Worker | app-worker | 192.168.0.14 | 應用工作節點 |

## 內部域名 (.detectviz.internal)

### 基礎設施域名
| 域名 | IP 位址 | 說明 |
|------|---------|------|
| `proxmox.detectviz.internal` | 192.168.0.2 | Proxmox Web UI |
| `ipmi.detectviz.internal` | 192.168.0.104 | IPMI 管理介面 |

### Kubernetes 集群域名
| 域名 | IP 位址 | 說明 |
|------|---------|------|
| `k8s-api.detectviz.internal` | 192.168.0.10 | Kubernetes API Server VIP |
| `master-1.detectviz.internal` | 192.168.0.11 | Master 節點 #1 |
| `master-2.detectviz.internal` | 192.168.0.12 | Master 節點 #2 |
| `master-3.detectviz.internal` | 192.168.0.13 | Master 節點 #3 |
| `app-worker.detectviz.internal` | 192.168.0.14 | Application Worker 節點 |

## 應用服務域名 (.detectviz.local)

### 主要應用服務
| 服務 | 域名 | IP 位址 | 說明 |
|------|------|---------|------|
| ArgoCD | `argocd.detectviz.local` | 192.168.0.10 | GitOps 控制面板 |

## DNS 配置參考

### dnsmasq 配置範例
```ini
# /etc/dnsmasq.d/detectviz.conf
domain=detectviz.internal
expand-hosts
local=/detectviz.internal/

# 主機記錄
address=/proxmox.detectviz.internal/192.168.0.2
address=/ipmi.detectviz.internal/192.168.0.104
address=/k8s-api.detectviz.internal/192.168.0.10
address=/master-1.detectviz.internal/192.168.0.11
address=/master-2.detectviz.internal/192.168.0.12
address=/master-3.detectviz.internal/192.168.0.13
address=/app-worker.detectviz.internal/192.168.0.14

# 應用服務
address=/argocd.detectviz.local/192.168.0.10

# 上游 DNS
server=8.8.8.8
server=1.1.1.1

listen-address=127.0.0.1,192.168.0.2
bind-interfaces
```

### /etc/hosts 參考
```bash
# Detectviz Cluster Hosts (自動生成)
192.168.0.11 master-1.detectviz.internal master-1
192.168.0.12 master-2.detectviz.internal master-2
192.168.0.13 master-3.detectviz.internal master-3
192.168.0.14 app-worker.detectviz.internal app-worker
192.168.0.10 k8s-api.detectviz.internal k8s-api
192.168.0.2 proxmox.detectviz.internal proxmox
192.168.0.104 ipmi.detectviz.internal ipmi
```

## 網路服務端口

### 基礎設施服務
| 服務 | 端口 | 協議 | 訪問方式 |
|------|------|------|----------|
| Proxmox Web UI | 8006 | HTTPS | https://proxmox.detectviz.internal:8006 |
| IPMI Web UI | 443 | HTTPS | https://ipmi.detectviz.internal |
| SSH | 22 | TCP | ssh user@hostname.detectviz.internal |
| Kubernetes API | 6443 | HTTPS | https://k8s-api.detectviz.internal:6443 |

### 應用服務
| 服務 | 端口 | 協議 | 說明 |
|------|------|------|------|
| ArgoCD UI | 80/443 | HTTP/HTTPS | GitOps 管理介面 |
| Grafana | 3000 | HTTP | 監控儀表板 |
| Prometheus | 9090 | HTTP | 指標收集 |

## 域名解析測試

### 基本測試命令
```bash
# 測試內部域名
dig master-1.detectviz.internal @192.168.0.2
dig app-worker.detectviz.internal @192.168.0.2

# 測試應用域名
dig argocd.detectviz.local @192.168.0.2

# 測試外部域名
dig google.com @192.168.0.2
```

### 批量測試
```bash
# 測試所有集群域名
for domain in \
  "proxmox.detectviz.internal" \
  "k8s-api.detectviz.internal" \
  "master-1.detectviz.internal" \
  "master-2.detectviz.internal" \
  "master-3.detectviz.internal" \
  "app-worker.detectviz.internal" \
  "argocd.detectviz.local"; do
  echo "Testing $domain:"
  dig $domain @192.168.0.2 +short
  echo
done
```

## 域名更新流程

### 添加新域名
1. 更新 DNS 配置 (`/etc/dnsmasq.d/detectviz.conf`)
2. 重新載入 dnsmasq: `systemctl reload dnsmasq`
3. 更新相關文檔
4. 測試域名解析

### 修改 IP 地址
1. 更新 Terraform 配置
2. 重新部署或修改 VM 網路
3. 更新 DNS 配置
4. 更新所有相關文檔

## 安全注意事項

### DNS 安全
- 限制 DNS 服務器訪問範圍
- 定期檢查 DNS 配置安全
- 監控異常查詢行為

### 域名管理
- 保持域名命名一致性
- 及時清理過期域名
- 文檔化域名變更

## 相關文檔

- [DNS 設置指南](dns-setup.md)
- [Bridge 配置指南](bridge-config.md)
- [網路優化指南](network-optimization.md)
- [Terraform 網路配置](../../terraform/README.md#網路配置)
