# OpenWrt for 京东云无线宝一代

基于官方 **[FanchmWrt](https://github.com/fanchmwrt/fanchmwrt)**（OpenWrt 25.12.4）给 **JDCloud RE-SP-01B** 出固件，固件名显示为 OpenWrt。

官方下载站有亚瑟 / 鲁班 / 雅典娜，**没有无线宝一代**。源码里有这个设备，所以用官方仓自己编。额外加上文件管理器和 Web 终端。

官网：https://www.fanchmwrt.com  
下载站（其他机型）：http://download.ttcoder.cn  
文档：http://doc.openappfilter.com/fanchmwrt

---

## 目标硬件

| 项目 | 值 |
|---|---|
| 设备 | JDCloud RE-SP-01B（京东云无线宝一代） |
| 兼容字符串 | `jdcloud,re-sp-01b` |
| SoC | MediaTek MT7621 |
| Flash | 32MB SPI-NOR，`firmware` 分区 **27328k** |
| RAM | 256MB DDR3 |
| 2.4G / 5G | MT7603 / MT7615 |
| 存储 | eMMC/SD + USB3 |

源码依据：`target/linux/ramips/image/mt7621.mk` 里的 `Device/jdcloud_re-sp-01b`。

---

## 固件里有什么

官方 `DEFAULT_PACKAGES.router` 已经带上：

- LuCI + `luci-theme-fanchmwrt`
- OAF 行为管理全家桶：`luci-app-fwx-appfilter` / dashboard / feature / user / record / macfilter ...
- `luci-app-ddns` / `upnp` / `wol` / `autoreboot` / `uhttpd`
- `block-mount`、USB 存储、ext4 / vfat

本工程额外加上：

| 功能 | 包 |
|---|---|
| 文件管理器 | `luci-app-filebrowser` |
| 应用程序中心 | `luci-app-fwx-app-center` |
| 广告过滤 | `adblock-fast`（默认开 AdAway） |
| Web 终端 | `luci-app-ttyd` |
| overlay 外置 | 插移动硬盘自动做 extroot |
| 存储补充 | exFAT / NTFS3 / 中文文件名 / e2fsprogs |

默认登录：`root`，密码空。后台地址 **http://192.168.12.1**。

---

## 怎么编

当前沙箱编不完完整工具链。把仓库推到 GitHub，用 Actions 编；或在本机 Ubuntu 22.04/24.04 跑。

### GitHub Actions（推荐）

1. 把本工程推到你的 GitHub 仓库
2. Actions -> `Build FanchmWrt` -> `Run workflow`
3. 约 1-3 小时后在 Artifacts 下载 `OpenWrt-jdcloud_re-sp-01b`

### 本机

```bash
sudo apt-get update
sudo apt-get install -y build-essential clang flex bison g++ gawk gettext git \
  libncurses-dev libssl-dev python3 python3-setuptools rsync unzip zlib1g-dev file wget

./scripts/build.sh
```

产物：

```
build/fanchmwrt/bin/targets/ramips/mt7621/*-jdcloud_re-sp-01b-squashfs-sysupgrade.bin
```

刷机步骤见 `docs/FLASH.md`。

---

## 目录

```
configs/fanchmwrt-25.12.seed   设备 + 额外包
configs/packages.apps          再加应用就取消注释
scripts/build.sh               一键构建（源码默认 fanchmwrt/fanchmwrt）
scripts/diy.sh                 第三方 feed / 补丁钩子
files/                         打进固件的 overlay
.github/workflows/build.yml    云编译
```

源码默认：

- 仓库 `https://github.com/fanchmwrt/fanchmwrt.git`
- 分支 `fanchmwrt-25.12.4`

FanchmWrt 25.12 用 **apk** 装插件，命令是 `apk add luci-app-xxx --allow-untrusted`。国内镜像见官方文档：http://doc.openappfilter.com/fanchmwrt/distfeeds.html
