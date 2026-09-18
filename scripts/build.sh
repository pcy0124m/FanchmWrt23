#!/usr/bin/env bash
#
# FanchmWrt 一键构建脚本
#
# 目标设备: 京东云无线宝一代 / JDCloud RE-SP-01B
# 硬件平台: MediaTek MT7621 (ramips/mt7621)
# 硬件规格: 32MB SPI-NOR Flash / 256MB DDR3 RAM
#
# 用法:
#   ./scripts/build.sh                全自动构建
#   ./scripts/build.sh --config-only  只生成 .config, 不编译 (适合先检查配置)
#   ./scripts/build.sh --menuconfig   先生成配置 -> 打开 menuconfig -> 再编译
#   ./scripts/build.sh --update-only  只更新源码和 feeds
#
# 可用环境变量:
#   SOURCE_REPO    源码仓库  默认官方 fanchmwrt/fanchmwrt
#   SOURCE_BRANCH  源码分支  默认 fanchmwrt-25.12.4
#   JOBS           编译并行度 默认 CPU 核数
#   DOWNLOAD_JOBS  下载并行度 默认 min(JOBS, 8)
#   SKIP_DISK_CHECK=1  跳过磁盘空间检查
#
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SOURCE_REPO="${SOURCE_REPO:-https://github.com/fanchmwrt/fanchmwrt.git}"
SOURCE_BRANCH="${SOURCE_BRANCH:-fanchmwrt-25.12.4}"
SOURCE_DIR="${SOURCE_DIR:-${PROJECT_ROOT}/build/fanchmwrt}"
SEED_CONFIG="${SEED_CONFIG:-${PROJECT_ROOT}/configs/fanchmwrt-25.12.seed}"
APPS_LIST="${APPS_LIST:-${PROJECT_ROOT}/configs/packages.apps}"
FILES_SRC="${PROJECT_ROOT}/files"

TARGET_SUBTARGET="ramips_mt7621"
TARGET_DEVICE="jdcloud_re-sp-01b"
OUTPUT_DIR="${SOURCE_DIR}/bin/targets/ramips/mt7621"

JOBS="${JOBS:-$(nproc 2>/dev/null || echo 2)}"
DOWNLOAD_JOBS="${DOWNLOAD_JOBS:-$(( JOBS > 8 ? 8 : JOBS ))}"
MIN_FREE_GB="${MIN_FREE_GB:-20}"

MODE="build"
for arg in "$@"; do
    case "${arg}" in
        --config-only) MODE="config" ;;
        --menuconfig)  MODE="menuconfig" ;;
        --update-only) MODE="update" ;;
        -h|--help)
            sed -n '3,21p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "未知参数: ${arg} (用 --help 查看用法)" >&2
            exit 2
            ;;
    esac
done

# ---------------------------------------------------------------------------
# 日志
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
    C_BLUE='\033[1;34m'; C_YELLOW='\033[1;33m'; C_RED='\033[1;31m'; C_GREEN='\033[1;32m'; C_OFF='\033[0m'
else
    C_BLUE=''; C_YELLOW=''; C_RED=''; C_GREEN=''; C_OFF=''
fi

log()  { printf "${C_BLUE}[%s]${C_OFF} %s\n" "$(date +%H:%M:%S)" "$*"; }
warn() { printf "${C_YELLOW}[警告]${C_OFF} %s\n" "$*" >&2; }
die()  { printf "${C_RED}[错误]${C_OFF} %s\n" "$*" >&2; exit 1; }
ok()   { printf "${C_GREEN}[完成]${C_OFF} %s\n" "$*"; }

# ---------------------------------------------------------------------------
# 1. 环境检查
# ---------------------------------------------------------------------------
check_host_deps() {
    log "检查主机依赖"

    local missing=()
    local tool
    for tool in git gcc g++ make gawk python3 unzip wget file; do
        command -v "${tool}" >/dev/null 2>&1 || missing+=("${tool}")
    done

    if [ "${#missing[@]}" -gt 0 ]; then
        warn "缺少以下命令: ${missing[*]}"
        case "$(uname -s)" in
            Linux)
                if command -v apt-get >/dev/null 2>&1; then
                    warn "Debian/Ubuntu 可执行:"
                    warn "  sudo apt-get update && sudo apt-get install -y build-essential clang flex bison g++ gawk \\"
                    warn "    gettext git libncurses-dev libssl-dev python3 python3-setuptools rsync unzip zlib1g-dev file wget"
                elif command -v dnf >/dev/null 2>&1; then
                    warn "Fedora/RHEL 可执行: sudo dnf install -y gcc gcc-c++ make gawk python3 git"
                fi
                ;;
            Darwin)
                warn "macOS 需要先装 Xcode Command Line Tools 与 gawk: brew install gawk"
                ;;
        esac
        die "请先补齐主机依赖再重试 (编译 OpenWrt 无法在缺少 gawk/gcc 的情况下进行)"
    fi

    # OpenWrt 的构建系统要求 gawk, 不接受 mawk / busybox awk
    if ! awk --version 2>/dev/null | grep -qi 'GNU Awk'; then
        warn "检测到系统 awk 不是 GNU awk。OpenWrt 构建系统严格要求 gawk,"
        warn "请安装 gawk 并确保它优先于 mawk (Ubuntu: sudo apt-get install -y gawk)"
        die "gawk 检查未通过"
    fi

    ok "主机依赖检查通过"
}

check_disk_space() {
    [ "${SKIP_DISK_CHECK:-0}" = "1" ] && { warn "已跳过磁盘空间检查"; return 0; }

    local probe_dir
    probe_dir="$(dirname "${SOURCE_DIR}")"
    mkdir -p "${probe_dir}"

    local free_gb
    free_gb="$(df -Pk "${probe_dir}" | awk 'NR==2 {printf "%d", $4/1024/1024}')"
    free_gb="${free_gb:-0}"

    log "可用磁盘空间: ${free_gb}GB (需要约 ${MIN_FREE_GB}GB)"
    if [ "${free_gb}" -lt "${MIN_FREE_GB}" ]; then
        die "磁盘空间不足。OpenWrt 完整编译需要约 20GB 以上(源码 + 工具链 + 输出)。
     可设置 SOURCE_DIR 指向更大的分区, 或用 SKIP_DISK_CHECK=1 强制继续(风险自负)。"
    fi
}

# ---------------------------------------------------------------------------
# 2. 获取源码
# ---------------------------------------------------------------------------
clone_source() {
    if [ -d "${SOURCE_DIR}/.git" ]; then
        log "源码已存在, 跳过克隆: ${SOURCE_DIR}"
        return 0
    fi

    log "克隆 ${SOURCE_REPO} (分支 ${SOURCE_BRANCH}) -> ${SOURCE_DIR}"
    mkdir -p "$(dirname "${SOURCE_DIR}")"
    git clone --depth 1 -b "${SOURCE_BRANCH}" "${SOURCE_REPO}" "${SOURCE_DIR}" \
        || die "源码克隆失败, 请检查网络与分支名 (当前分支: ${SOURCE_BRANCH})"
    ok "源码克隆完成"
}

update_feeds() {
    log "更新并安装 feeds (首次约 5-15 分钟)"
    (
        cd "${SOURCE_DIR}"
        ./scripts/feeds update -a || die "feeds update 失败, 通常是网络问题, 重试即可"
        ./scripts/feeds install -a || die "feeds install 失败"
    )
    ok "feeds 就绪"
}

# ---------------------------------------------------------------------------
# 3. 生成 .config
# ---------------------------------------------------------------------------
merge_overlay_files() {
    [ -d "${FILES_SRC}" ] || return 0
    log "合并自定义 overlay 到 buildroot/files"
    mkdir -p "${SOURCE_DIR}/files"
    cp -a "${FILES_SRC}/." "${SOURCE_DIR}/files/"
    ok "overlay 已合并"
}

build_config() {
    [ -f "${SEED_CONFIG}" ] || die "找不到种子配置: ${SEED_CONFIG}"

    log "基于种子配置生成 .config"
    cp "${SEED_CONFIG}" "${SOURCE_DIR}/.config"

    local requested=()
    if [ -f "${APPS_LIST}" ]; then
        log "追加应用清单: ${APPS_LIST}"
        local pkg
        while IFS= read -r pkg; do
            case "${pkg}" in
                ''|'#'*) continue ;;
            esac
            pkg="${pkg%%[[:space:]]*}"
            printf 'CONFIG_PACKAGE_%s=y\n' "${pkg}" >> "${SOURCE_DIR}/.config"
            requested+=("${pkg}")
        done < "${APPS_LIST}"
    fi

    (
        cd "${SOURCE_DIR}"
        make defconfig >/dev/null || die "make defconfig 执行失败"
    )
    ok ".config 生成完成"

    # ---- 校验: 目标与关键包必须真的落进 .config ----
    log "校验目标平台与关键包"
    local fatal=0

    local must_have=(
        "CONFIG_TARGET_ramips=y"
        "CONFIG_TARGET_ramips_mt7621=y"
        "CONFIG_TARGET_ramips_mt7621_DEVICE_${TARGET_DEVICE}=y"
        "CONFIG_PACKAGE_luci-theme-fanchmwrt=y"
        "CONFIG_PACKAGE_luci-app-fwx-appfilter=y"
        "CONFIG_PACKAGE_luci-app-filebrowser=y"
        "CONFIG_PACKAGE_luci-app-adblock-fast=y"
        "CONFIG_PACKAGE_luci-app-fwx-app-center=y"
        "CONFIG_PACKAGE_e2fsprogs=y"
    )

    local sym
    for sym in "${must_have[@]}"; do
        if grep -qxF "${sym}" "${SOURCE_DIR}/.config"; then
            log "  [OK] ${sym}"
        else
            printf "${C_RED}  [缺失]${C_OFF} %s\n" "${sym}" >&2
            fatal=1
        fi
    done

    if [ "${fatal}" -eq 1 ]; then
        die "关键配置缺失。最常见原因是源码分支不是官方 FanchmWrt, 或该分支没有 ${TARGET_DEVICE}。
     请使用默认仓库 https://github.com/fanchmwrt/fanchmwrt.git 和分支 fanchmwrt-25.12.4"
    fi

    if [ "${#requested[@]}" -gt 0 ]; then
        local dropped=()
        local p
        for p in "${requested[@]}"; do
            grep -qxF "CONFIG_PACKAGE_${p}=y" "${SOURCE_DIR}/.config" || dropped+=("${p}")
        done
        if [ "${#dropped[@]}" -gt 0 ]; then
            warn "以下追加应用在当前源里不存在, 已被 defconfig 忽略: ${dropped[*]}"
            warn "请核对 configs/packages.apps 中的包名拼写"
        fi
    fi

    ok "配置校验通过"
}

# ---------------------------------------------------------------------------
# 4. 编译
# ---------------------------------------------------------------------------
download_sources() {
    log "下载软件包源码 (并行度 ${DOWNLOAD_JOBS})"
    (
        cd "${SOURCE_DIR}"
        make download -j"${DOWNLOAD_JOBS}" || warn "部分源码下载失败, 编译时会重试 (常见于个别上游链接临时不可用)"
    )
    ok "源码下载阶段结束"
}

compile() {
    log "开始编译 (并行度 ${JOBS}), 首次编译通常 2-5 小时, 请耐心等待"
    (
        cd "${SOURCE_DIR}"
        if ! make -j"${JOBS}"; then
            warn "并行编译失败。正在用单线程 + 详细日志重跑以定位真实错误..."
            warn "定位命令: cd ${SOURCE_DIR} && make -j1 V=s"
            return 1
        fi
    )
    ok "编译完成"
}

report() {
    echo
    echo "============================================================"
    ok "FanchmWrt 构建成功"
    echo "============================================================"
    echo "输出目录: ${OUTPUT_DIR}"
    echo
    ls -lh "${OUTPUT_DIR}"/*.bin 2>/dev/null || warn "未找到 .bin 产物, 请检查 ${OUTPUT_DIR}"
    echo
    echo "刷机请用 squashfs-sysupgrade 那个文件, 步骤见 docs/FLASH.md"
    echo "initramfs-kernel 是救援镜像, 仅在设备无法正常启动时使用"
}

# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------
cd "${PROJECT_ROOT}"

check_host_deps
check_disk_space
clone_source

if [ "${MODE}" = "update" ]; then
    update_feeds
    ok "源码与 feeds 已更新"
    exit 0
fi

update_feeds

# 加载用户自定义钩子 (内部可继续使用上面定义的变量)
# shellcheck source=/dev/null
. "${PROJECT_ROOT}/scripts/diy.sh"

merge_overlay_files
build_config

if [ "${MODE}" = "config" ]; then
    ok "仅生成配置模式, 已停止。配置位于: ${SOURCE_DIR}/.config"
    exit 0
fi

if [ "${MODE}" = "menuconfig" ]; then
    # 注意: 这里不能再调用 build_config, 否则会用种子配置覆盖掉用户刚保存的改动
    log "打开 menuconfig, 保存退出后继续编译"
    ( cd "${SOURCE_DIR}" && make menuconfig )
fi

download_sources
compile
report
