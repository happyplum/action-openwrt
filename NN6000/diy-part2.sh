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

# ------------------------------- Main source started -------------------------------
# Set default IP address
default_ip="192.168.7.1"
ip_regex="^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"
# Modify default IP if an argument is provided and it matches the IP format
[[ -n "${1}" && "${1}" != "${default_ip}" && "${1}" =~ ${ip_regex} ]] && {
    echo "Modify default IP address to: ${1}"
    sed -i "/lan) ipad=\${ipaddr:-/s/\${ipaddr:-\"[^\"]*\"}/\${ipaddr:-\"${1}\"}/" package/base-files/*/bin/config_generate
}
# ------------------------------- Main source ends -------------------------------

# ------------------------------- Other started -------------------------------
#
# Apply patch
# git apply ../config/patches/{0001*,0002*}.patch --directory=feeds/luci
#
# ------------------------------- Other ends -------------------------------

# passwall2
# merge_package https://github.com/xiaorouji/openwrt-passwall2 openwrt-passwall2/luci-app-passwall2

# passwall
merge_package https://github.com/xiaorouji/openwrt-passwall openwrt-passwall/luci-app-passwall

# smartDNS #2025年4月6日 根据仓库代码，openwrt-smartdns/需要拷贝到/feeds/packages/net/smartdns/
# 2025年12月17日 尝试使用src-link来使用merge-package/custom下载的smartdns
merge_package https://github.com/pymumu/luci-app-smartdns luci-app-smartdns

./scripts/feeds update -a

# smart好像需要update完了单独处理下
# 2025年12月17日 好像一直失败，不太清楚，暂时先屏蔽掉用原生的
merge_package https://github.com/pymumu/openwrt-smartdns openwrt-smartdns
rm -rf feeds/packages/net/smartdns
mv package/custom/openwrt-smartdns feeds/packages/net/smartdns

./scripts/feeds install -a

echo "========================="
echo " DIY2 配置完成……"
