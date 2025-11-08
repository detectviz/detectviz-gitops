# 安裝 qemu-guest-agent

1. qemu-guest-agent 安裝
```bash
sudo apt-get install qemu-guest-agent
```

2. qemu-guest-agent 啟動
```bash
sudo systemctl enable qemu-guest-agent
sudo systemctl start qemu-guest-agent
```

3. qemu-guest-agent 狀態
```bash
sudo systemctl status qemu-guest-agent
```
