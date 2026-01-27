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
ln -s package/base-files/files/usr/share/v2ray/geoip.dat package/base-files/files/usr/share/xray/geoip.dat
ln -s package/base-files/files/usr/share/v2ray/geosite.dat package/base-files/files/usr/share/xray/geosite.dat
# ------------------------------- Main source ends -------------------------------

# ------------------------------- Other started -------------------------------
#
# 1.设置OpenWrt 文件的下载仓库
# mosdns
rm -rf package/mosdns
git clone --depth=1 -b v5 --single-branch https://github.com/sbwml/luci-app-mosdns package/mosdns

#smartdns
rm -rf package/luci-app-smartdns
rm -rf feeds/packages/net/smartdns
git clone --depth=1 --single-branch https://github.com/pymumu/luci-app-smartdns package/luci-app-smartdns
git clone --depth=1 --single-branch https://github.com/pymumu/openwrt-smartdns feeds/packages/net/smartdns

# Apply patch
# git apply ../config/patches/{0001*,0002*}.patch --directory=feeds/luci
#
# ------------------------------- Other ends -------------------------------

./scripts/feeds install -a

echo "========================="
echo " DIY2 配置完成……"
