一个自用的 openwrt 打包仓库

目前设备 r68s

项目参考
[P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt)
[ophub/amlogic-s9xxx-openwrt](https://github.com/ophub/amlogic-s9xxx-openwrt)

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