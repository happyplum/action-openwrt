#!/bin/bash
#========================================================================================================================
# https://github.com/ophub/amlogic-s9xxx-openwrt
# Description: Automatically Build OpenWrt for Amlogic s9xxx tv box
# Function: Diy script (After Update feeds, Modify the default IP, hostname, theme, add/remove software packages, etc.)
# Source code repository: https://github.com/coolsnowwolf/lede / Branch: master
#========================================================================================================================

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

# 优化：main 分支直接用本次 checkout 的 sysctl 文件，避免每次构建去 raw.githubusercontent.com 拉自己；
# 其他仓库/分支保持旧逻辑（从远端 main 拉），以免本地文件与远端不一致时悄悄改变行为。
sysctl_dir=package/base-files/files/etc/sysctl.d
if [[ "${GITHUB_REPOSITORY:-}" == "happyplum/action-openwrt" && "${GITHUB_REF:-}" == "refs/heads/main" && -d "${GITHUB_WORKSPACE:-}/config" ]]; then
    mkdir -p "${sysctl_dir}"
    install -m 0644 "${GITHUB_WORKSPACE}/config/"{0-base,0-v4,0-v6,1-netfilter}.conf "${sysctl_dir}/" || exit $?
else
    rm -rf ${sysctl_dir}/0-base.conf
    wget -P ${sysctl_dir} https://raw.githubusercontent.com/happyplum/action-openwrt/refs/heads/main/config/0-base.conf
    rm -rf ${sysctl_dir}/0-v4.conf
    wget -P ${sysctl_dir} https://raw.githubusercontent.com/happyplum/action-openwrt/refs/heads/main/config/0-v4.conf
    rm -rf ${sysctl_dir}/0-v6.conf
    wget -P ${sysctl_dir} https://raw.githubusercontent.com/happyplum/action-openwrt/refs/heads/main/config/0-v6.conf
    rm -rf ${sysctl_dir}/1-netfilter.conf
    wget -P ${sysctl_dir} https://raw.githubusercontent.com/happyplum/action-openwrt/refs/heads/main/config/1-netfilter.conf
fi

# Lock cpufreq governor to performance at boot (silently skipped if cpufreq unavailable, e.g. no PMIC)
sed -i '/exit 0/i for cpu in /sys/devices/system/cpu/cpufreq/policy*; do [ -d "${cpu}" ] && echo "performance" > "${cpu}/scaling_governor"; done' package/base-files/files/etc/rc.local

# ------------------------------- Main source ends -------------------------------

# ------------------------------- Other started -------------------------------
#
# 1.设置OpenWrt 文件的下载仓库
# mosdns
rm -rf package/mosdns
git clone --depth=1 -b v5 --single-branch https://github.com/sbwml/luci-app-mosdns package/mosdns

#smartdns
rm -rf feeds/packages/net/smartdns
git clone --depth=1 https://github.com/pymumu/openwrt-smartdns feeds/packages/net/smartdns
rm -rf feeds/luci/applications/luci-app-smartdns
git clone --depth=1 https://github.com/pymumu/luci-app-smartdns feeds/luci/applications/luci-app-smartdns
# Remove MIRROR_HASH to skip hash verification (pymumu's pre-set hashes don't match actual git archive output)
sed -i '/PKG_MIRROR_HASH\|MIRROR_HASH/d' feeds/packages/net/smartdns/Makefile

# Apply patch
# git apply ../config/patches/{0001*,0002*}.patch --directory=feeds/luci
#
# ------------------------------- Other ends -------------------------------

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
bash "${SCRIPT_DIR}/../upgrade-rust.sh" || exit $?
bash "${SCRIPT_DIR}/../pin-golang.sh" || exit $?
./scripts/feeds install -a

echo "========================="
echo " DIY2 配置完成……"
