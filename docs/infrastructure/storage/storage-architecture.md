# DetectViz 儲存架構設計

## 概述

本文件說明 DetectViz 平台的混合儲存架構設計。

## 硬體規格

| 設備類型 | 型號 | 容量 | 介面 | 用途 |
|----------|------|------|------|------|
| SATA SSD | Acer RE100 | 512GB | SATA | 系統儲存 |
| NVMe SSD | TEAM MP44 | 2TB | PCIe Gen4 | 高效能資料儲存 |

## 儲存架構

### 分層設計
- **系統層**：SATA SSD - Proxmox 系統和核心服務
- **高效層**：NVMe SSD - VM 系統碟、資料庫、AI 模型
- **備份層**：SATA 分區 - 備份儲存

### 技術選型
- **檔案系統**：EXT4 over LVM-Thin
- **儲存管理**：Proxmox Storage
- **快照支持**：LVM Thin Pool

## 容量規劃

### 資源分配
| 用途 | 容量 | 儲存類型 |
|------|------|----------|
| Proxmox 系統 | 50GB | SATA |
| VM 系統碟 | 620GB | NVMe |
| 應用資料 | 800GB+ | NVMe |
| 備份儲存 | 200GB+ | SATA |

## 效能優化

### I/O 調優
```bash
# NVMe 優化設置
echo "none" > /sys/block/nvme0n1/queue/scheduler
echo 1024 > /sys/block/nvme0n1/queue/nr_requests
```

### 快取策略
- VM 系統碟：Write-back
- 資料庫：Write-through
- 備份：直接寫入

## 相關文檔

- [儲存設置指南](storage-setup.md)