# Terraform 的 VM 配置參數

## Clone 與初始化配置參數
- `bios = "ovmf"`：若 template 為 UEFI，可改 `ovmf` 提升相容性
- `clone.full = true`：所有節點都從 **template VM (9000) 克隆
- `agent { enabled = true, type = "virtio" }`：啟用 QEMU Guest Agent
- `user_account.username = "ubuntu"`：每台 VM 預設使用 ubuntu 帳號
- `user_account.keys = ["ssh-rsa <your_public_key> <your_username>"]`：每台 VM 預設使用 ssh-rsa 公鑰

## Disk 配置參數
- `replicate = false`：若單節點 Proxmox，可設 `false`，避免 clone 多餘檢查

## Network 配置參數
- `mtu = 1450`：
- `gateway = 192.168.0.1` 
- `dns.server = 8.8.8.8` 
- `bridge = vmbr0`
- `control_plane_vip = 192.168.0.10`   (HA kube-vip)
- `domain = detectviz.internal`

## 後續流程設定參數

- 輸出段落中的 `next_steps_guide` 與 `verification_commands` 已完整產生，是對後續自動化（Ansible、Kubeadm）的良好引導。
- 自動生成 `ansible/inventory.ini` 檔案  
- 輸出 kubeadm 初始化指令：

```bash
sudo kubeadm init --control-plane-endpoint="192.168.0.10:6443" --pod-network-cidr="10.244.0.0/16" --service-cidr="10.96.0.0/12" --apiserver-advertise-address="192.168.0.11"
```
- 測試網路連通性：

```bash
for ip in 192.168.0.11 192.168.0.12 192.168.0.13 192.168.0.14; do ping -c2 $ip; done
```  
- 提供 SSH 測試指令：

```bash
ssh ubuntu@192.168.0.11 "hostname"
```

## 檔案產出檢查

- `../ansible/inventory.ini`   
- `../hosts-fragment.txt`   
- `cluster_summary`：集群摘要
- `network_config`：網路配置
- `resource_allocation`：資源分配