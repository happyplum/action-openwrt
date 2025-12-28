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
#
# Modify default theme（FROM uci-theme-bootstrap CHANGE TO luci-theme-material）
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' ./feeds/luci/collections/luci/Makefile

# Add autocore support for armvirt
sed -i 's/DEPENDS:=@(.*/DEPENDS:=@(TARGET_bcm27xx||TARGET_bcm53xx||TARGET_ipq40xx||TARGET_ipq806x||TARGET_ipq807x||TARGET_mvebu||TARGET_rockchip||TARGET_armvirt) \\/g' package/emortal/autocore/Makefile

# Modify default IP（FROM 192.168.1.1 CHANGE TO 192.168.31.4）
sed -i 's/192.168.1.1/192.168.7.1/g' package/base-files/files/bin/config_generate

# 2024年8月30日屏蔽3528和3588的编译，被强制选中了，而且需要python2
# sed -i '/^UBOOT_TARGETS := rk3528-evb rk3588-evb/s/^/#/' package/boot/uboot-rk35xx/Makefile

# 优化
rm -rf package/base-files/files/etc/sysctl.d/base.conf
wget -P package/base-files/files/etc/sysctl.d https://raw.githubusercontent.com/happyplum/OpenWrt/main/R68S/config/base.conf
rm -rf package/base-files/files/etc/sysctl.d/pro.conf
wget -P package/base-files/files/etc/sysctl.d https://raw.githubusercontent.com/happyplum/OpenWrt/main/R68S/config/pro.conf
rm -rf package/base-files/files/etc/sysctl.d/99-custom.conf
wget -P package/base-files/files/etc/sysctl.d https://raw.githubusercontent.com/happyplum/OpenWrt/main/R68S/config/99-custom.conf
rm -rf package/base-files/files/etc/balance_irq
wget -P package/base-files/files/etc  https://raw.githubusercontent.com/happyplum/OpenWrt/main/R68S/config/balance_irq
rm -rf package/base-files/files/usr/sbin/balethirq.pl
wget -P package/base-files/files/usr/sbin https://raw.githubusercontent.com/unifreq/openwrt_packit/master/files/balethirq.pl
# rm -rf package/base-files/files/usr/sbin/fixcpufreq.pl
# wget -P package/base-files/files/usr/sbin https://raw.githubusercontent.com/unifreq/openwrt_packit/master/files/fixcpufreq.pl
# sed -i 's/schedutil/performance/g'  package/base-files/files/usr/sbin/fixcpufreq.pl

# 添加自启动
chmod 755 -R package/base-files/files/usr/sbin
sed -i '/exit 0/i\/usr/sbin/balethirq.pl' package/base-files/files/etc/rc.local

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
# Add luci-app-amlogic
merge_package https://github.com/ophub/luci-app-amlogic luci-app-amlogic/luci-app-amlogic
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

# passwall2
# merge_package https://github.com/xiaorouji/openwrt-passwall2 openwrt-passwall2/luci-app-passwall2

# passwall
merge_package https://github.com/xiaorouji/openwrt-passwall openwrt-passwall/luci-app-passwall

# smartDNS #2025年4月6日 根据仓库代码，openwrt-smartdns/需要拷贝到/feeds/packages/net/smartdns/
# 2025年12月17日 尝试使用src-link来使用merge-package/custom下载的smartdns
# merge_package https://github.com/pymumu/luci-app-smartdns luci-app-smartdns

./scripts/feeds update -a

# smart好像需要update完了单独处理下
# 2025年12月17日 好像一直失败，不太清楚，暂时先屏蔽掉用原生的
# merge_package https://github.com/pymumu/openwrt-smartdns openwrt-smartdns
# rm -rf feeds/packages/net/smartdns
# mv package/custom/openwrt-smartdns feeds/packages/net/smartdns

./scripts/feeds install -a

echo "========================="
echo " DIY2 配置完成……"
