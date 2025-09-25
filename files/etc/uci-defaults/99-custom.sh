#!/bin/sh
# iStoreOS 首次运行时
LOGFILE="/tmp/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >>$LOGFILE
# 设置默认防火墙规则，方便虚拟机首次访问 WebUI
# uci set firewall.@zone[1].input='ACCEPT'

# 设置主机名映射，解决安卓原生 TV 无法联网的问题
uci add dhcp domain
uci set "dhcp.@domain[-1].name=time.android.com"
uci set "dhcp.@domain[-1].ip=203.107.6.88"

# 设置主机名
uci set system.@system[0].hostname='iStoreOS'
uci set system.@system[0].timezone='CST-8'
uci set system.@system[0].zonename='Asia/Shanghai'

# 设置默认语言为简体中文
uci set luci.main.lang='zh_cn'
# 保存设置
uci commit system
uci commit luci

# 设置所有网口可访问网页终端
uci delete ttyd.@ttyd[0].interface

# 设置编译作者信息
FILE_PATH="/etc/openwrt_release"
NEW_DESCRIPTION="iStoreOS 24.10.2"
sed -i "s/DISTRIB_DESCRIPTION='[^']*'/DISTRIB_DESCRIPTION='$NEW_DESCRIPTION'/" "$FILE_PATH"

# 修改banner并删除/etc/banner1文件夹
cp /etc/banner1/banner /etc/
rm -r /etc/banner1

# 【网络设置-static】
uci set network.lan.proto='static'
uci set network.lan.ipaddr='192.168.5.88'
uci set network.lan.netmask='255.255.255.0'
uci set network.lan.gateway='192.168.5.1'
uci set network.lan.dns='223.5.5.5'
uci commit network

# 【网络设置-dhcp】
# ---计算网卡数量
count=0
ifnames=""
for iface in /sys/class/net/*; do
    iface_name=$(basename "$iface")
    # 检查是否为物理网卡（排除回环设备和无线设备）
    if [ -e "$iface/device" ] && echo "$iface_name" | grep -Eq '^eth|^en'; then
        count=$((count + 1))
        ifnames="$ifnames $iface_name"
    fi
done
# ---删除多余空格
ifnames=$(echo "$ifnames" | awk '{$1=$1};1')

# ---开始网络设置
if [ "$count" -eq 1 ]; then
    # 单网口设备 类似于NAS模式 动态获取ip模式 具体ip地址取决于上一级路由器给它分配的ip 也方便后续你使用web页面设置旁路由
    # 单网口设备 不支持修改ip 不要在此处修改ip 单网口采用dhcp模式 删除默认的192.168.1.1
    uci set network.lan.proto='dhcp'
    uci delete network.lan.ipaddr
    uci delete network.lan.netmask
    uci delete network.lan.gateway     
    uci delete network.lan.dns 
    uci commit network
elif [ "$count" -gt 1 ]; then
    # 提取第一个接口作为WAN
    wan_ifname=$(echo "$ifnames" | awk '{print $1}')
    # 剩余接口保留给LAN
    lan_ifnames=$(echo "$ifnames" | cut -d ' ' -f2-)
    # 设置WAN接口基础配置
    uci set network.wan=interface
    # 提取第一个接口作为WAN
    uci set network.wan.device="$wan_ifname"
    # WAN接口默认DHCP
    uci set network.wan.proto='dhcp'
    # 设置WAN6绑定网口eth0
    uci set network.wan6=interface
    uci set network.wan6.device="$wan_ifname"
    # 更新LAN接口成员
    # 查找对应设备的section名称
    section=$(uci show network | awk -F '[.=]' '/\.@?device\[\d+\]\.name=.br-lan.$/ {print $2; exit}')
    if [ -z "$section" ]; then
        echo "error：cannot find device 'br-lan'." >>$LOGFILE
    else
        # 删除原来的ports列表
        uci -q delete "network.$section.ports"
        # 添加新的ports列表
        for port in $lan_ifnames; do
            uci add_list "network.$section.ports"="$port"
        done
        echo "ports of device 'br-lan' are update." >>$LOGFILE
    fi
    # LAN口设置静态IP
    uci set network.lan.proto='static'
    # 多网口设备 支持修改为别的ip地址,别的地址应该是网关地址，形如192.168.xx.1 项目说明里都强调过。
    # 大家不能胡乱修改哦 比如有人修改为192.168.100.55 这是错误的理解 这个项目不能提前设置旁路地址
    # 旁路的设置分2类情况,情况一是单网口的设备,默认是DHCP模式，ip应该在上一级路由器里查看。之后进入web页在设置旁路。
    # 情况二旁路由如果是多网口设备，也应当用网关访问网页后，在自行在web网页里设置。总之大家不能直接在代码里修改旁路网关。千万不要徒增bug啦。
    uci set network.lan.ipaddr='192.168.100.1'
    uci set network.lan.netmask='255.255.255.0'
fi

# 设置所有网口可连接 SSH
uci set dropbear.@dropbear[0].Interface=''
uci commit

exit 0
