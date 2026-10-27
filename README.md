一个自用的 openwrt 打包仓库

目前设备 r68s

项目参考
[P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt)
[ophub/amlogic-s9xxx-openwrt](https://github.com/ophub/amlogic-s9xxx-openwrt)

## NSY-G68-PLUS 交换机模式

默认使用 DSA，定时构建也使用 DSA；手动构建可通过 `SWMODE` 显式选择 `switch`。
DIY2 按模式将 DTS、`02_network` 和 `.config` 模板写入 OpenWrt 构建目录，
并选择对应驱动包；缺失任一模板时停止构建。DSA 使用 `kmod-dsa-rtl8365mb`，
网口为 `lan1` 至 `lan4` 和 `wan`，旧交换机节点在 DSA DTS 中禁用。
选定模式后，构建目录只保留生效的 `02_network`，避免 `board_detect` 依次执行两份模式模板而覆盖网络配置。

源码固定为 ImmortalWrt `openwrt-25.12` 的
`84b665b5de552e297d0f7d755b88a46fc0cfeb13`，对应 Linux 6.12.112；
源码提交只在该设备工作流的 `REPO_COMMIT` 维护，缓存按提交隔离。
软件源提交由 `NSY-G68-PLUS/feeds.conf.default` 维护，DIY2 不再次更新 feeds。
DIY2 在覆盖板级文件前校验真实内核系列为 6.12，镜像补丁检查或应用失败时停止。

SGMII、XPCS、CombPHY 等已由该源码基线提供的补丁直接复用上游版本；
板级新增补丁保留在 `NSY-G68-PLUS/userpatches/target/linux/rockchip/patches-6.12`。
RTL8367S 的补充驱动使用外部接口 ID 配置寄存器，并修正 SDS 间接读取，
按同驱动已有约定锁住完整事务、有限等待 busy 清除和传播 I/O 错误。
寄存器访问依据见 [原始驱动评审](https://lists.openwall.net/netdev/2022/05/10/384)。

本地回归覆盖模式文件选择、版本与补丁失败处理以及实际补丁函数的寄存器访问；
测试命令同下文。固件网口仍需在真实设备核对链路、LAN DHCP、WAN 和 VLAN，
自动化回归不能代替刷机后的硬件验证。

## Go 构建版本

NN6000、R68S、NSY-G68-PLUS 和 SystemReady 的 DIY2 在最后一次更新 feeds 后，
统一调用根目录 `pin-golang.sh`，将 `feeds/packages/lang/golang` 固定为
ImmortalWrt packages 提交 `0ee3fbc2992c75b2668933467479343c5e4c75e9` 的完整 Go 1.27.2 构建配方，
以满足 Xray 26.10.21 对 Go 1.27 的要求。版本只在该脚本维护，保留官方源码校验。
该处理会清理旧 Go 安装链接、刷新索引并重新安装 Go 构建包；失败时停止 DIY2。
固定后不可再次更新 packages 源。Ophub R68S 仅打包已有 rootfs，不适用此处理。

定向测试：`python3 -B -m unittest discover -s tests -v`（在 Linux/WSL 中执行，需要 Bash）。
Go 包固定会影响这些固件内的全部 Go 软件包，发布前需核对实际 host Go 版本、Xray 和完整固件构建结果。

WSL
由于 WSL 的 PATH 中包含带有空格的 Windows 路径，有可能会导致编译失败，请在 make 前面加上：

```bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
```

OpenWrt 必选项

```
Target System  -> Arm SystemReady (EFI) compliant
Subtarget      -> 64-bit (armv8) machines
Target Profile -> Generic EFI Boot
Target Images  -> tar.gz

OR

Target System  -> QEMU ARM Virtual Machine
Subtarget      -> QEMU ARMv8 Virtual Machine (cortex-a53)
Target Profile -> Default
Target Images  -> tar.gz


Kernel modules -> Wireless Drivers -> kmod-brcmfmac(SDIO)
                                   -> kmod-brcmutil
                                   -> kmod-cfg80211
                                   -> kmod-mac80211


Languages -> Perl
             -> perl-http-date
             -> perlbase-file
             -> perlbase-getopt
             -> perlbase-time
             -> perlbase-unicode
             -> perlbase-utf8
          -> Python
             -> Python3-ctypes
             -> Python3-logging
             -> Python3-yaml


Network -> File Transfer -> curl、wget-ssl
        -> Version Control Systems -> git
        -> WirelessAPD   -> hostapd-common
                         -> wpa-cli
                         -> wpad-mesh-openssl
        -> iw


Utilities -> Compression -> bsdtar、pigz
          -> Disc -> blkid、fdisk、lsblk、parted
          -> Editors -> nano、vim
          -> Filesystem -> attr、btrfs-progs(Build with zstd support)、chattr、dosfstools、
                           e2fsprogs、f2fs-tools、f2fsck、lsattr、mkf2fs、xfs-fsck、xfs-mkfs
          -> Shells -> bash
          -> Time Zone info -> zoneinfo-america、zoneinfo-asia、zoneinfo-core、zoneinfo-europe (other)
          -> acpid、coremark、coreutils(-> coreutils-base64、coreutils-dd、coreutils-df、coreutils-nohup、
             coreutils-tail、coreutils-timeout、coreutils-touch、coreutils-tr、coreutils-truncate)、
             gawk、getopt、jq、lm-sensors、losetup、pv、tar、uuidgen
```

# 2026年1月14日
发现node组件会大量增加编译时间，进行移除

# 2026年1月18日
nginx一开NN6000和G68S感觉性能都会下降，用起来有点不舒服