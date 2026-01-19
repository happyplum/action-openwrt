# 完整硬件配置：

CPU：瑞芯微RK3568处理器，四核Cortex-A55架构，最高2.0GHz主频 25
内存：4GB LPDDR4 22
存储：16GB EMMC 22
网络接口：2个2.5G网口（RTL8125B）+ 2个1G网口（RTL8211F）

# 刷机
R68s刷机方式：
1.解压固件压缩包里面的 img文件，改名为aaa.img(改名是为了后面方便操作）

2.点击系统-文件传输-选择本地文件，将aaa.img上传（将文件上传到'/tmp/upload/'）

3.通过系统-TTYD终端或别的工具，ssh连接到r68s

4.输入命令
dd if=/tmp/upload/aaa.img of=/dev/mmcblk0
等待出现下列字样
xxxxxxx+0 records in
xxxxxxx+0 records out

5.断电，重新启动r68s，固件更新完毕。

如果刷机失败，重启后蓝灯不亮，应该会进入maskrom模式，用usb线刷即可。

==============================================

如果想进入刷机模式，可以ssh链接后
输入命令 dd if=/dev/zero of=/dev/mmcblk0 bs=8M count=1
然后重启，可以进入maskrom刷机模式

==============================================
最后，如果严重变砖，可以拆开外壳，在电路板背面找到maskrom标记的两个金属点
用镊子先短接的同时，通电即可进入usb线刷模式。