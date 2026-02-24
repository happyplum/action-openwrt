#!/bin/bash

# 项目配置
GITHUB_REPO="https://github.com/happyplum/action-openwrt.git"
GITHUB_BRANCH="main"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 版本号设置为编译日期
date_version=$(date +"%Y%m%d%H")
echo $date_version > version

# 从 GitHub 稀疏克隆多个目录
clone_from_github() {
    local tmp_dir=$(mktemp -d)
    echo "从 GitHub 克隆: NSY-G68-PLUS/userpatches 和 NSY-G68-PLUS/patch"
    git clone --depth=1 --filter=blob:none --sparse "${GITHUB_REPO}" "${tmp_dir}" 2>/dev/null
    (cd "${tmp_dir}" && git sparse-checkout set "NSY-G68-PLUS/userpatches" "NSY-G68-PLUS/patch" 2>/dev/null)
    if [[ -d "${tmp_dir}/NSY-G68-PLUS/userpatches" ]]; then
        mkdir -p "./userpatches"
        cp -r "${tmp_dir}/NSY-G68-PLUS/userpatches/"* "./userpatches/" 2>/dev/null
        echo "userpatches 克隆完成"
    else
        echo "警告: 无法克隆 userpatches"
    fi
    if [[ -d "${tmp_dir}/NSY-G68-PLUS/patch" ]]; then
        cp -r "${tmp_dir}/NSY-G68-PLUS/patch" "./" 2>/dev/null
        echo "patch 克隆完成"
    else
        echo "警告: 无法克隆 patch"
    fi
    rm -rf "${tmp_dir}"
}

# 检查并获取所需文件
setup_files() {
    local need_clone=false
    if [[ ! -d "${SCRIPT_DIR}/userpatches" ]]; then
        need_clone=true
    fi
    if [[ ! -d "${SCRIPT_DIR}/patch" ]]; then
        need_clone=true
    fi
    if [[ "${need_clone}" == "true" ]]; then
        clone_from_github
    else
        echo "使用本地文件..."
        [[ -d "${SCRIPT_DIR}/userpatches" ]] && rsync -a "${SCRIPT_DIR}/userpatches/" ./
        [[ -d "${SCRIPT_DIR}/patch" ]] && cp -r "${SCRIPT_DIR}/patch" ./
    fi
}

# 设置所需文件
setup_files

# 修正自动编译 openwrt 时 rust 选项导致错误
if [[ -f "feeds/packages/lang/rust/Makefile" ]]; then
    if grep -q '\-\-ci' feeds/packages/lang/rust/Makefile; then
        sed -i 's/--ci [a-z]*/--ci false/g' feeds/packages/lang/rust/Makefile
        echo "Rust 编译修正完成（替换已有参数）"
    else
        sed -i '/^\s*\$(\PYTHON) \$(\HOST_BUILD_DIR)\/x\.py \\/a\\t\t--ci false \\' feeds/packages/lang/rust/Makefile
        echo "Rust 编译修正完成（添加新参数）"
    fi
fi

# U-Boot Makefile 添加 G68-Plus 机型定义
if [[ -f "package/boot/uboot-rockchip/Makefile" ]]; then
    sed -i '/^# RK3568 boards$/a\
\
define U-Boot/nsy-g68-plus-rk3568\
  $(U-Boot/rk3568/Default)\
  NAME:=NSY G68 PLUS\
  BUILD_DEVICES:= \\\
    nsy_g68-plus\
endef' package/boot/uboot-rockchip/Makefile

    sed -i '/^UBOOT_TARGETS := \\/a\
  nsy-g68-plus-rk3568 \\' package/boot/uboot-rockchip/Makefile
    echo "U-Boot 机型定义完成"
fi

# mt76 固件路径修改
if [[ -f "package/kernel/mt76/Makefile" ]]; then
    sed -i '/[ \t]*\$([^)]*PKG_BUILD_DIR[^)]*)\/firmware\/mt7615_rom_patch\.bin[ \t]*\\$/a\
		.\/firmware\/mt7615e_rf.bin \\' package/kernel/mt76/Makefile

    sed -i '/[ \t]*$(PKG_BUILD_DIR)\/firmware\/mt7916_wa.bin[ \t]*\\$/c\
		.\/firmware\/mt7916_wa.bin \\' package/kernel/mt76/Makefile
    sed -i '/[ \t]*$(PKG_BUILD_DIR)\/firmware\/mt7916_wm.bin[ \t]*\\$/c\
		.\/firmware\/mt7916_wm.bin \\' package/kernel/mt76/Makefile
    sed -i '/[ \t]*$(PKG_BUILD_DIR)\/firmware\/mt7916_rom_patch.bin[ \t]*\\$/c\
		.\/firmware\/mt7916_rom_patch.bin \\' package/kernel/mt76/Makefile
    sed -i '/[ \t]*\.\/firmware\/mt7916_rom_patch\.bin[ \t]*\\$/a\
		.\/firmware\/mt7916_eeprom.bin \\' package/kernel/mt76/Makefile
    echo "mt76 固件路径修改完成"
fi

# 启用无线扩展配置 (config-6.6, config-6.12)
CONFIGS6=("target/linux/generic/config-6.6" "target/linux/generic/config-6.12")
for cfg in "${CONFIGS6[@]}"; do
    if [[ ! -f "$cfg" ]]; then
        echo "[跳过] 文件不存在: $cfg" >&2
        continue
    fi
    sed -i -e 's/^# CONFIG_WEXT_CORE is not set$/CONFIG_WEXT_CORE=y/' \
           -e 's/^# CONFIG_WEXT_PRIV is not set$/CONFIG_WEXT_PRIV=y/' \
           -e 's/^# CONFIG_WEXT_PROC is not set$/CONFIG_WEXT_PROC=y/' \
           -e 's/^# CONFIG_WEXT_SPY is not set$/CONFIG_WEXT_SPY=y/' \
           -e 's/^# CONFIG_WIRELESS_EXT is not set$/CONFIG_WIRELESS_EXT=y/' "$cfg" &&
    echo "[成功] 已修改: $cfg" || echo "[失败] 修改出错: $cfg"
done

# rockchip 平台配置
CONFIG_DIR="target/linux/rockchip/armv8"
CONFIG_PATTERN="$CONFIG_DIR/config-*"
for cfg in $CONFIG_PATTERN; do
    [[ -f "$cfg" ]] || continue
    echo CONFIG_KEYBOARD_ADC=y >> $cfg
    echo CONFIG_ROCKCHIP_SARADC=y >> $cfg
    echo "# CONFIG_CRYPTO_MANAGER_DISABLE_TESTS is not set" >> $cfg
    echo "# CONFIG_CRYPTO_MANAGER_EXTRA_TESTS is not set" >> $cfg
done
echo "rockchip 平台配置完成"

# 添加 G68-Plus 设备定义到 armv8.mk
if [[ -f "target/linux/rockchip/image/armv8.mk" ]]; then
    echo -e "\\ndefine Device/nsy_g68-plus
  \$(Device/rk3568)
  DEVICE_VENDOR := NSY
  DEVICE_MODEL := G68-PLUS
  SOC := rk3568
  DEVICE_DTS := rk3568-nsy-g68-plus
  UBOOT_DEVICE_NAME := nsy-g68-plus-rk3568
  BOOT_FLOW := pine64-img
  DEVICE_PACKAGES := kmod-dsa-rtl8365mb
endef
TARGET_DEVICES += nsy_g68-plus" >> target/linux/rockchip/image/armv8.mk
    echo "设备定义添加完成"
fi

# 应用 patch 目录下的补丁
echo "应用 patch 目录下的补丁..."
if [[ -d "patch" ]]; then
    for patch_file in patch/*.patch; do
        [[ -f "$patch_file" ]] || continue
        echo "处理: $patch_file"
        git apply --stat "$patch_file" 2>/dev/null
        git apply --check "$patch_file" 2>/dev/null || { echo "检查失败: $patch_file"; continue; }
        git apply "$patch_file" && echo "应用成功: $patch_file" || echo "应用失败: $patch_file"
    done
fi

echo "编译 执行完成"

echo "开始 DIY2 配置……"
echo "========================="
# ------------------------------- Custom Package -------------------------------
./scripts/feeds update -a
# ------------------------------- Custom Package -------------------------------

# ------------------------------- Main source started -------------------------------
# Set default IP address
default_ip="192.168.1.1"
ip_regex="^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"
# Modify default IP if an argument is provided and it matches the IP format
[[ -n "${1}" && "${1}" != "${default_ip}" && "${1}" =~ ${ip_regex} ]] && {
    echo "Modify default IP address to: ${1}"
    sed -i "/lan) ipad=\${ipaddr:-/s/\${ipaddr:-\"[^\"]*\"}/\${ipaddr:-\"${1}\"}/" package/base-files/*/bin/config_generate
}

# 优化
rm -rf package/base-files/files/etc/sysctl.d/0-base.conf
wget -P package/base-files/files/etc/sysctl.d https://raw.githubusercontent.com/happyplum/action-openwrt/refs/heads/main/config/0-base.conf
rm -rf package/base-files/files/etc/sysctl.d/0-v4.conf
wget -P package/base-files/files/etc/sysctl.d https://raw.githubusercontent.com/happyplum/action-openwrt/refs/heads/main/config/0-v4.conf
rm -rf package/base-files/files/etc/sysctl.d/0-v6.conf
wget -P package/base-files/files/etc/sysctl.d https://raw.githubusercontent.com/happyplum/action-openwrt/refs/heads/main/config/0-v6.conf
rm -rf package/base-files/files/etc/sysctl.d/1-netfilter.conf
wget -P package/base-files/files/etc/sysctl.d https://raw.githubusercontent.com/happyplum/action-openwrt/refs/heads/main/config/1-netfilter.conf

# 下载v2ray的dat数据
rm -rf feeds/packages/net/v2ray-geodata
rm -rf package/base-files/files/usr/share/v2ray/geoip.dat
wget -P package/base-files/files/usr/share/v2ray https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat
rm -rf package/base-files/files/usr/share/v2ray/geosite.dat
wget -P package/base-files/files/usr/share/v2ray https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat
rm -rf package/base-files/files/usr/share/xray
mkdir package/base-files/files/usr/share/xray
ln -s /usr/share/v2ray/geoip.dat package/base-files/files/usr/share/xray/geoip.dat
ln -s /usr/share/v2ray/geosite.dat package/base-files/files/usr/share/xray/geosite.dat
# ------------------------------- Main source ends -------------------------------

# ------------------------------- Other started -------------------------------
#
# 1.设置OpenWrt 文件的下载仓库
# mosdns
rm -rf package/mosdns
git clone --depth=1 -b v5 --single-branch https://github.com/sbwml/luci-app-mosdns package/mosdns

#smartdns
# rm -rf package/luci-app-smartdns
# rm -rf feeds/packages/net/smartdns
# git clone --depth=1 --single-branch https://github.com/pymumu/luci-app-smartdns package/luci-app-smartdns
# git clone --depth=1 --single-branch https://github.com/pymumu/openwrt-smartdns feeds/packages/net/smartdns
# sed -i 's/227eef2dfffb56445145e7b8a76f6d6fa678ce3e99aceec58f7d35564f4cfafd/4401734712dd034eb1088ce440d1bc64d053dfcd6f63f66c08cd48ab68593042/g' feeds/packages/net/smartdns/Makefile
# sed -i 's/609fec024396a3a26278ef9fe7bd49aeca478e3163fc53c699a5f402fa0320f0/f8bfb91ae0992dd62392ebb2b7d968d514f7cbc3cc6a5d975dafdd6b27bf0a0c/g' feeds/packages/net/smartdns/Makefile

# ------------------------------- Other ends -------------------------------

./scripts/feeds install -a

echo "========================="
echo " DIY2 配置完成……"