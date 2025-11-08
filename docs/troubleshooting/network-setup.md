# Proxmox network 設定


---

## 一、確認 Proxmox 主機網路狀態

執行於 **Proxmox 主機**：

```bash
ip a
cat /etc/network/interfaces
ip route show
ping -c3 8.8.8.8
```

**確認如下輸出**：

```bash
auto vmbr0
iface vmbr0 inet static
	address 192.168.0.2/24
	gateway 192.168.0.1
	bridge-ports enp4s0
	bridge-stp off
	bridge-fd 0

source /etc/network/interfaces.d/*
default via 192.168.0.1 dev vmbr0 proto kernel onlink
192.168.0.0/24 dev vmbr0 proto kernel scope link src 192.168.0.2
PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data.
64 bytes from 8.8.8.8: icmp_seq=1 ttl=110 time=6.60 ms
64 bytes from 8.8.8.8: icmp_seq=2 ttl=110 time=8.05 ms
64 bytes from 8.8.8.8: icmp_seq=3 ttl=110 time=6.65 ms

--- 8.8.8.8 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2002ms
rtt min/avg/max/mdev = 6.604/7.104/8.054/0.672 ms
```

---

## 二、在節點（VM）內確認路由與網關

在 **K8s VM** 執行：

```bash
ip route
ping -c3 192.168.0.1
ping -c3 8.8.8.8
```

**確認如下輸出**：

### vm-1 (192.168.0.11)

```
default via 192.168.0.1 dev eth0 proto static
10.244.0.0/24 dev cni0 proto kernel scope link src 10.244.0.1
blackhole 10.244.25.64/26 proto bird
192.168.0.0/24 dev eth0 proto kernel scope link src 192.168.0.11
PING 192.168.0.1 (192.168.0.1) 56(84) bytes of data.

--- 192.168.0.1 ping statistics ---
3 packets transmitted, 0 received, 100% packet loss, time 2025ms

PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data.

--- 8.8.8.8 ping statistics ---
3 packets transmitted, 0 received, 100% packet loss, time 2031ms
```

### vm-2 (192.168.0.12)

```bash
ubuntu@vm-2:~$ ip route
ping -c3 192.168.0.1
ping -c3 8.8.8.8
default via 192.168.0.1 dev eth0 proto static
blackhole 10.244.205.192/26 proto bird
10.244.224.192/26 via 192.168.0.14 dev tunl0 proto bird onlink
10.244.236.64/26 via 192.168.0.13 dev tunl0 proto bird onlink
10.244.242.192/26 via 192.168.0.15 dev tunl0 proto bird onlink
192.168.0.0/24 dev eth0 proto kernel scope link src 192.168.0.12
PING 192.168.0.1 (192.168.0.1) 56(84) bytes of data.
64 bytes from 192.168.0.1: icmp_seq=1 ttl=64 time=0.715 ms
64 bytes from 192.168.0.1: icmp_seq=2 ttl=64 time=0.707 ms
64 bytes from 192.168.0.1: icmp_seq=3 ttl=64 time=0.694 ms

--- 192.168.0.1 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2055ms
rtt min/avg/max/mdev = 0.694/0.705/0.715/0.008 ms
PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data.
64 bytes from 8.8.8.8: icmp_seq=1 ttl=110 time=10.8 ms
64 bytes from 8.8.8.8: icmp_seq=2 ttl=110 time=9.77 ms
64 bytes from 8.8.8.8: icmp_seq=3 ttl=110 time=14.3 ms

--- 8.8.8.8 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2004ms
rtt min/avg/max/mdev = 9.769/11.620/14.254/1.912 ms
```

### vm-3 (192.168.0.13)

```
ping -c3 192.168.0.1
ping -c3 8.8.8.8
default via 192.168.0.1 dev eth0 proto static
10.244.205.192/26 via 192.168.0.12 dev tunl0 proto bird onlink
10.244.224.192/26 via 192.168.0.14 dev tunl0 proto bird onlink
blackhole 10.244.236.64/26 proto bird
10.244.242.192/26 via 192.168.0.15 dev tunl0 proto bird onlink
192.168.0.0/24 dev eth0 proto kernel scope link src 192.168.0.13
PING 192.168.0.1 (192.168.0.1) 56(84) bytes of data.
64 bytes from 192.168.0.1: icmp_seq=1 ttl=64 time=0.550 ms
64 bytes from 192.168.0.1: icmp_seq=2 ttl=64 time=0.550 ms
64 bytes from 192.168.0.1: icmp_seq=3 ttl=64 time=0.351 ms

--- 192.168.0.1 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2055ms
rtt min/avg/max/mdev = 0.351/0.483/0.550/0.093 ms
PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data.
64 bytes from 8.8.8.8: icmp_seq=1 ttl=110 time=63.4 ms
64 bytes from 8.8.8.8: icmp_seq=2 ttl=110 time=21.9 ms
64 bytes from 8.8.8.8: icmp_seq=3 ttl=110 time=93.4 ms

--- 8.8.8.8 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2003ms
rtt min/avg/max/mdev = 21.898/59.581/93.435/29.330 ms
```

### vm-4 (192.168.0.14)

```
default via 192.168.0.1 dev eth0 proto static
10.244.205.192/26 via 192.168.0.12 dev tunl0 proto bird onlink
blackhole 10.244.224.192/26 proto bird
10.244.224.202 dev calib2caa65200e scope link
10.244.224.207 dev cali000d0b78e6f scope link
10.244.224.208 dev cali15b0a008db8 scope link
10.244.224.209 dev cali062c61a735e scope link
10.244.224.210 dev cali0b3ecae2a68 scope link
10.244.224.232 dev calic5ea84a9f54 scope link
10.244.224.233 dev cali61a9554ce92 scope link
10.244.236.64/26 via 192.168.0.13 dev tunl0 proto bird onlink
10.244.242.192/26 via 192.168.0.15 dev tunl0 proto bird onlink
192.168.0.0/24 dev eth0 proto kernel scope link src 192.168.0.14
PING 192.168.0.1 (192.168.0.1) 56(84) bytes of data.
64 bytes from 192.168.0.1: icmp_seq=1 ttl=64 time=0.778 ms
64 bytes from 192.168.0.1: icmp_seq=2 ttl=64 time=0.610 ms
64 bytes from 192.168.0.1: icmp_seq=3 ttl=64 time=0.564 ms

--- 192.168.0.1 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2034ms
rtt min/avg/max/mdev = 0.564/0.650/0.778/0.091 ms
PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data.
64 bytes from 8.8.8.8: icmp_seq=1 ttl=110 time=8.76 ms
64 bytes from 8.8.8.8: icmp_seq=2 ttl=110 time=10.8 ms
64 bytes from 8.8.8.8: icmp_seq=3 ttl=110 time=8.65 ms

--- 8.8.8.8 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2004ms
rtt min/avg/max/mdev = 8.646/9.412/10.837/1.008 ms
```

### vm-5 (192.168.0.15)

```
ip route
ping -c3 192.168.0.1
ping -c3 8.8.8.8
default via 192.168.0.1 dev eth0 proto static
10.244.205.192/26 via 192.168.0.12 dev tunl0 proto bird onlink
10.244.224.192/26 via 192.168.0.14 dev tunl0 proto bird onlink
10.244.236.64/26 via 192.168.0.13 dev tunl0 proto bird onlink
blackhole 10.244.242.192/26 proto bird
10.244.242.197 dev califa28b480347 scope link
10.244.242.218 dev calif481462ee00 scope link
10.244.242.222 dev cali1da2eb5548c scope link
10.244.242.224 dev califc3f0579f52 scope link
10.244.242.226 dev calicec17af8cb7 scope link
10.244.242.250 dev calif61e6c43f30 scope link
10.244.242.251 dev calif00a657b7ee scope link
10.244.242.252 dev cali2beeb8f6856 scope link
10.244.242.253 dev calic750930defb scope link
192.168.0.0/24 dev eth0 proto kernel scope link src 192.168.0.15
PING 192.168.0.1 (192.168.0.1) 56(84) bytes of data.
64 bytes from 192.168.0.1: icmp_seq=1 ttl=64 time=0.533 ms
64 bytes from 192.168.0.1: icmp_seq=2 ttl=64 time=0.477 ms
64 bytes from 192.168.0.1: icmp_seq=3 ttl=64 time=0.513 ms

--- 192.168.0.1 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2043ms
rtt min/avg/max/mdev = 0.477/0.507/0.533/0.023 ms
PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data.
64 bytes from 8.8.8.8: icmp_seq=1 ttl=110 time=6.71 ms
64 bytes from 8.8.8.8: icmp_seq=2 ttl=110 time=9.15 ms
64 bytes from 8.8.8.8: icmp_seq=3 ttl=110 time=8.36 ms

--- 8.8.8.8 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2003ms
rtt min/avg/max/mdev = 6.711/8.073/9.146/1.014 ms
```
