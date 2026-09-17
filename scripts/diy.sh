#!/usr/bin/env bash
# FanchmWrt 构建自定义钩子
#
# 执行时机: 在 feeds install 之后、生成 .config 之前
# 调用方式: 由 scripts/build.sh 以 source 方式加载, 因此可以直接使用:
#   SOURCE_DIR    buildroot 源码目录
#   PROJECT_ROOT  本工程根目录
#   JOBS          并行度
#   log()/warn()  日志函数
#
# 默认行为: 如果存在 configs/feeds.extra, 就把它里面的 feed 注册进构建系统。
#          文件格式与 OpenWrt 的 feeds.conf 一致, 例如:
#              src-git kenzo https://github.com/kenzok8/openwrt-packages.git
#              src-git small https://github.com/kenzok8/small.git
#
# 需要更深的定制 (打补丁 / 改源码) 时, 直接把命令追加到本文件末尾。

set -euo pipefail

EXTRA_FEEDS="${PROJECT_ROOT}/configs/feeds.extra"

if [ -f "${EXTRA_FEEDS}" ]; then
    log "检测到第三方 feed 清单, 正在注册: ${EXTRA_FEEDS}"
    while IFS= read -r feed_line; do
        case "${feed_line}" in
            ''|'#'*)
                continue
                ;;
        esac
        if grep -qxF "${feed_line}" "${SOURCE_DIR}/feeds.conf.default"; then
            log "  已存在, 跳过: ${feed_line}"
        else
            echo "${feed_line}" >> "${SOURCE_DIR}/feeds.conf.default"
            log "  已添加: ${feed_line}"
        fi
    done < "${EXTRA_FEEDS}"

    (
        cd "${SOURCE_DIR}"
        ./scripts/feeds update -a
        ./scripts/feeds install -a
    )
fi

# ---------------------------------------------------------------------------
# 把源码里所有 FanchmWrt 字样替换为 OpenWrt
# 这样系统信息 / LuCI / banner 等全部显示 OpenWrt
# ---------------------------------------------------------------------------
log "将源码中的 FanchmWrt 替换为 OpenWrt"
(
    cd "${SOURCE_DIR}"
    # 替换所有文本文件中的 FanchmWrt -> OpenWrt, 跳过 .git 和二进制
    find . -type f \
        -not -path './.git/*' \
        -not -path './bin/*' \
        -not -path './build_dir/*' \
        -not -path './staging_dir/*' \
        -not -path './tmp/*' \
        -exec grep -Il 'FanchmWrt' {} + 2>/dev/null \
    | xargs -r sed -i 's/FanchmWrt/OpenWrt/g; s/fanchmwrt/openwrt/g'
)
log "替换完成"

# ---------------------------------------------------------------------------
# 在这里追加你自己的源码级定制, 例如:
#
# ( cd "${SOURCE_DIR}" && git apply "${PROJECT_ROOT}/patches/0001-my-fix.patch" )
#
# 或者直接覆盖某个软件包:
#
# cp -a "${PROJECT_ROOT}/custom/luci-app-xxx" "${SOURCE_DIR}/package/custom/"
# ---------------------------------------------------------------------------
