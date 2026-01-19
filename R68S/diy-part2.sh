#!/bin/bash
#========================================================================================================================
# https://github.com/ophub/amlogic-s9xxx-openwrt
# Description: Automatically Build OpenWrt for Amlogic s9xxx tv box
# Function: Diy script (After Update feeds, Modify the default IP, hostname, theme, add/remove software packages, etc.)
# Source code repository: https://github.com/coolsnowwolf/lede / Branch: master
#========================================================================================================================

echo "开始 DIY2 配置……"
echo "========================="

function merge_package(){
    repo=`echo $1 | rev | cut -d'/' -f 1 | rev`
    pkg=`echo $2 | rev | cut -d'/' -f 1 | rev`
    # find package/ -follow -name $pkg -not -path "package/custom/*" | xargs -rt rm -rf
    git clone --depth=1 --single-branch $1
    mv $2 package/custom/
    rm -rf $repo
}
function drop_package(){
    find package/ -follow -name $1 -not -path "package/custom/*" | xargs -rt rm -rf
}
function merge_feed(){
    if [ ! -d "feed/$1" ]; then
        echo >> feeds.conf.default
        echo "src-git $1 $2" >> feeds.conf.default
    fi
    ./scripts/feeds update $1
    ./scripts/feeds install -a -p $1
}
rm -rf package/custom; mkdir package/custom

# ------------------------------- Custom Package -------------------------------
# Add luci-app-amlogic
merge_package https://github.com/ophub/luci-app-amlogic luci-app-amlogic/luci-app-amlogic

# passwall
merge_package https://github.com/xiaorouji/openwrt-passwall openwrt-passwall/luci-app-passwall

# 2025年12月17日 尝试使用src-link来使用merge-package/custom下载的smartdns
merge_package https://github.com/pymumu/luci-app-smartdns luci-app-smartdns

./scripts/feeds update -a
# ------------------------------- Custom Package -------------------------------

# ------------------------------- Main source started -------------------------------
#

# Modify default IP
#sed -i 's/192.168.1.1/192.168.7.1/g' package/base-files/files/bin/config_generate

# Modify default theme
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile

# Modify hostname
sed -i 's/OpenWrt/Happyplum-Router/g' package/base-files/files/bin/config_generate

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
wget -P package/base-files/files/etc/sysctl.d https://raw.githubusercontent.com/happyplum/OpenWrt/main/config/0-base.conf
rm -rf package/base-files/files/etc/sysctl.d/0-v4.conf
wget -P package/base-files/files/etc/sysctl.d https://raw.githubusercontent.com/happyplum/OpenWrt/main/config/0-v4.conf
rm -rf package/base-files/files/etc/sysctl.d/0-v6.conf
wget -P package/base-files/files/etc/sysctl.d https://raw.githubusercontent.com/happyplum/OpenWrt/main/config/0-v6.conf
rm -rf package/base-files/files/etc/sysctl.d/1-netfilter.conf
wget -P package/base-files/files/etc/sysctl.d https://raw.githubusercontent.com/happyplum/OpenWrt/main/config/1-netfilter.conf
rm -rf package/base-files/files/etc/balance_irq
wget -P package/base-files/files/etc  https://raw.githubusercontent.com/happyplum/OpenWrt/main/R68S/interface/balance_irq
rm -rf package/base-files/files/usr/sbin/balethirq.pl
wget -P package/base-files/files/usr/sbin https://raw.githubusercontent.com/unifreq/openwrt_packit/master/files/balethirq.pl
# rm -rf package/base-files/files/usr/sbin/fixcpufreq.pl
# wget -P package/base-files/files/usr/sbin https://raw.githubusercontent.com/unifreq/openwrt_packit/master/files/fixcpufreq.pl
# sed -i 's/schedutil/performance/g'  package/base-files/files/usr/sbin/fixcpufreq.pl

# 添加自启动
chmod 755 -R package/base-files/files/usr/sbin
sed -i '/exit 0/i\/usr/sbin/balethirq.pl' package/base-files/files/etc/rc.local
# sed -i '/exit 0/i\/usr/sbin/fixcpufreq.pl' package/base-files/files/etc/rc.local

# 下载singbox的db数据
# rm -rf package/base-files/files/usr/share/singbox/geoip.db
# wget -P package/base-files/files/usr/share/singbox https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.db
# rm -rf package/base-files/files/usr/share/singbox/geosite.db
# wget -P package/base-files/files/usr/share/singbox https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.db

# 下载v2ray的dat数据
# rm -rf package/base-files/files/usr/share/v2ray/geoip.dat
# wget -P package/base-files/files/usr/share/v2ray https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat
# rm -rf package/base-files/files/usr/share/v2ray/geosite.dat
# wget -P package/base-files/files/usr/share/v2ray https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat

# ------------------------------- Main source ends -------------------------------

# ------------------------------- Other started -------------------------------
#
# 1.设置OpenWrt 文件的下载仓库
sed -i "s|amlogic_firmware_repo.*|amlogic_firmware_repo 'https://github.com/happyplum/action-openwrt'|g" package/custom/luci-app-amlogic/root/etc/config/amlogic
# 2.设置 Releases 里 Tags 的关键字
sed -i "s|OpenWrt_armv8_r68s|g" package/custom/luci-app-amlogic/root/etc/config/amlogic
# 3.设置 Releases 里 OpenWrt 文件的后缀
sed -i "s|.img.gz|.OPENWRT_SUFFIX|g" package/custom/luci-app-amlogic/root/etc/config/amlogic
# 4.设置 OpenWrt 内核的下载路径
# sed -i "s|amlogic_kernel_path.*|amlogic_kernel_path 'https://github.com/USERNAME/REPOSITORY'|g" package/custom/luci-app-amlogic/root/etc/config/amlogic

#
# Apply patch
# git apply ../config/patches/{0001*,0002*}.patch --directory=feeds/luci
#
# ------------------------------- Other ends -------------------------------

# smartDNS #2025年4月6日 根据仓库代码，openwrt-smartdns/需要拷贝到/feeds/packages/net/smartdns/
# smart好像需要update完了单独处理下
# merge_package https://github.com/pymumu/openwrt-smartdns openwrt-smartdns
# rm -rf feeds/packages/net/smartdns
# mv package/custom/openwrt-smartdns feeds/packages/net/smartdns

./scripts/feeds install -a

echo "========================="
echo " DIY2 配置完成……"
