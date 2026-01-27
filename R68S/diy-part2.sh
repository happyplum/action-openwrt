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
wget -P package/base-files/files/etc/sysctl.d https://raw.githubusercontent.com/happyplum/action-openwrt/refs/heads/main/config/0-base.conf
rm -rf package/base-files/files/etc/sysctl.d/0-v4.conf
wget -P package/base-files/files/etc/sysctl.d https://raw.githubusercontent.com/happyplum/action-openwrt/refs/heads/main/config/0-v4.conf
rm -rf package/base-files/files/etc/sysctl.d/0-v6.conf
wget -P package/base-files/files/etc/sysctl.d https://raw.githubusercontent.com/happyplum/action-openwrt/refs/heads/main/config/0-v6.conf
rm -rf package/base-files/files/etc/sysctl.d/1-netfilter.conf
wget -P package/base-files/files/etc/sysctl.d https://raw.githubusercontent.com/happyplum/action-openwrt/refs/heads/main/config/1-netfilter.conf
rm -rf package/base-files/files/etc/balance_irq
wget -P package/base-files/files/etc  https://raw.githubusercontent.com/happyplum/action-openwrt/refs/heads/main/R68S/interface/balance_irq
rm -rf package/base-files/files/usr/sbin/balethirq.pl
wget -P package/base-files/files/usr/sbin https://raw.githubusercontent.com/unifreq/openwrt_packit/master/files/balethirq.pl
rm -rf package/base-files/files/usr/sbin/fixcpufreq.pl
wget -P package/base-files/files/usr/sbin https://raw.githubusercontent.com/unifreq/openwrt_packit/master/files/fixcpufreq.pl
sed -i 's/schedutil/performance/g'  package/base-files/files/usr/sbin/fixcpufreq.pl

# 添加自启动
chmod 755 -R package/base-files/files/usr/sbin
sed -i '/exit 0/i\/usr/sbin/balethirq.pl' package/base-files/files/etc/rc.local
sed -i '/exit 0/i\/usr/sbin/fixcpufreq.pl' package/base-files/files/etc/rc.local

# 下载singbox的db数据
rm -rf package/base-files/files/usr/share/singbox/geoip.db
wget -P package/base-files/files/usr/share/singbox https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.db
rm -rf package/base-files/files/usr/share/singbox/geosite.db
wget -P package/base-files/files/usr/share/singbox https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.db

# 下载v2ray的dat数据
rm -rf package/base-files/files/usr/share/v2ray/geoip.dat
wget -P package/base-files/files/usr/share/v2ray https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat
rm -rf package/base-files/files/usr/share/v2ray/geosite.dat
wget -P package/base-files/files/usr/share/v2ray https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat
rf -rf package/base-files/files/usr/share/xray
mkdir package/base-files/files/usr/share/xray
ln -s package/base-files/files/usr/share/v2ray/geoip.dat package/base-files/files/usr/share/xray/geoip.dat
ln -s package/base-files/files/usr/share/v2ray/geosite.dat package/base-files/files/usr/share/xray/geosite.dat

# ------------------------------- Main source ends -------------------------------

# ------------------------------- Other started -------------------------------
#
# 1.设置OpenWrt 文件的下载仓库
#
# Apply patch
# git apply ../config/patches/{0001*,0002*}.patch --directory=feeds/luci
#
# ------------------------------- Other ends -------------------------------
./scripts/feeds install -a

echo "========================="
echo " DIY2 配置完成……"
