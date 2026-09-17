# 刷机指南 — 京东云无线宝一代（JDCloud RE-SP-01B）

针对 **已刷 Breed** 的设备。官方下载站没有这一代现成包，刷的是本工程编出来的 `*-squashfs-sysupgrade.bin`。

官方文档（其他机型）：http://doc.openappfilter.com/fanchmwrt/flash.html

---

## 刷之前

1. 用 Breed 备份整片 32MB Flash 和 EEPROM。`factory` 分区（`0x40000`，64KB）是无线校准数据，丢了 WiFi 会废。
2. OpenWrt 只写 `firmware` 分区（`0x50000` 起 27328k），不动 Breed。
3. 刷完京东云原厂积分/远程管理失效。

---

## 进 Breed

断电 -> 按住 RESET -> 通电按 3-5 秒 -> 电脑网线接 **LAN** -> 浏览器 `http://192.168.1.1`（Breed 仍是 1.1）。拿不到地址就手动设 `192.168.1.2/24`。

先备份「编程器固件 / 整片 Flash」和 EEPROM，存两份。

---

## 刷 FanchmWrt

文件：

```
build/fanchmwrt/bin/targets/ramips/mt7621/
  *-jdcloud_re-sp-01b-squashfs-sysupgrade.bin   <-- 刷这个
  *-jdcloud_re-sp-01b-initramfs-kernel.bin      <-- 救砖用
```

Breed -> 固件更新 -> 上传 sysupgrade.bin -> 闪存布局保持自动识别 -> 上传完不要断电。

等 2-3 分钟。电脑改成自动获取 IP，或手动 `192.168.12.2/24`，访问 **http://192.168.12.1**。

登录：

- 用户：`root`
- 密码：空（直接回车）

---

## 刷完

1. 空密码只适合局域网。要暴露到外面再设密码。
2. `网络 -> 无线`：设 SSID + WPA2 后再启用（默认关射频）。
3. 文件管理器：`系统 -> File Browser`。
4. 应用程序：官方应用中心。
5. 广告过滤：`服务 -> AdBlock Fast`，默认开 AdAway 列表。
6. overlay：插上 USB 移动硬盘。
   - 分区 LABEL 做成 `FCM_OVERLAY`（ext4），或
   - 整盘只有一个**空分区**（无文件系统）
   检测到后会格式化（仅空分区）、拷 overlay、写 fstab，然后**自动重启一次**。之后可写空间在硬盘上。
   有数据的盘不会动。拔掉硬盘会回到 Flash overlay，不会变砖。

装插件（25.12 用 apk）：

```bash
apk update --allow-untrusted
apk add luci-app-xxx --allow-untrusted
```

国内镜像：http://doc.openappfilter.com/fanchmwrt/distfeeds.html  
ramips/mt7621 对应 ImmortalWrt 的 `mipsel_24kc` 软件源，版本用相近的 25.12.0 即可。

---

## 救砖

能进 Breed：重刷 sysupgrade，或写回整片备份。

无线很弱：Breed 里恢复 EEPROM。

Breed 也进不去：编程器写整片备份。所以备份一定要做。
