# 可选应用

官方已内置 OAF、仪表盘、DDNS、UPnP、WOL。
本工程另外加了：文件管理器、应用程序中心、广告过滤、overlay 迁硬盘。

再加应用：编辑 `configs/packages.apps`，去掉行首 `#`，重新编译。
刷好后也可以：

```bash
apk update --allow-untrusted
apk add luci-app-xxx --allow-untrusted
```

`firmware` 分区上限 **27328 KB**。官方 FanchmWrt 本身比毛坯 OpenWrt 重一些，再加包前先看体积。

## 建议按需加

| 包 | 用途 | 注意 |
|---|---|---|
| `luci-app-samba4` | Windows 共享 | 会拉 samba4，体积大 |
| `luci-app-minidlna` | DLNA 投屏 | 轻 |
| `luci-app-aria2` | HTTP/BT 下载 | MT7621 CPU 吃紧，少挂任务 |
| `luci-app-zerotier` | 异地组网 | 官方默认已有 `kmod-tun` |
| `luci-app-nlbwmon` | 按设备统计流量 | 轻，实用 |

## 不要装

| 包 | 原因 |
|---|---|
| `netdata` | 单包约 26MB，32MB Flash 装不下 |
| `dockerd` / `luci-app-dockerman` | MT7621 + 256MB 跑容器没意义 |

官方插件安装说明：http://doc.openappfilter.com/fanchmwrt/package-install.html
