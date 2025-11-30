# Info Check 硬體資訊查詢

## Hardware

### 硬體資訊查詢（讀取 SMBIOS 資訊）

1. 使用 `dmidecode` 命令讀取主機板的 `Serial Number`
```bash
root@proxmox:/home# dmidecode -t baseboard | grep "Serial Number" | awk -F': ' '{print $2}'
```

### Server

### Storage

### Networking

### Power

### Cooling