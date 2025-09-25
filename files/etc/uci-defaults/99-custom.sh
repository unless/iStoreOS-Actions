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
##uci delete ttyd.@ttyd[0].interface

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
end0_exists=0
eth0_exists=0
eth1_exists=0

# 检测物理网卡
for iface in /sys/class/net/*; do
    iface_name=$(basename "$iface")
    # 检查是否为物理网卡
    if [ -e "$iface/device" ] && echo "$iface_name" | grep -Eq '^eth|^en|^end'; then
        count=$((count + 1))
        ifnames="$ifnames $iface_name"
        
        # 记录特定网卡的存在
        if [ "$iface_name" = "end0" ]; then
            end0_exists=1
        elif [ "$iface_name" = "eth0" ]; then
            eth0_exists=1
        elif [ "$iface_name" = "eth1" ]; then
            eth1_exists=1
        fi
    fi
done

# 删除多余空格
ifnames=$(echo "$ifnames" | awk '{$1=$1};1')

echo "检测到的物理网卡: $ifnames"
echo "网卡数量: $count"

# 开始网络设置
if [ "$count" -eq 1 ]; then
    # 单网口设备 - 作为LAN
    uci set network.lan.proto='dhcp'
    uci delete network.lan.ipaddr
    uci delete network.lan.netmask
    uci delete network.lan.gateway     
    uci delete network.lan.dns 
    uci commit network
    echo "单网口设备配置为LAN(DHCP模式)"
    
elif [ "$count" -gt 1 ]; then
    # 多网口设备
    if [ $end0_exists -eq 1 ] && [ $eth0_exists -eq 1 ]; then
        # end0和eth0同时存在
        wan_ifname="eth0"
        lan_ifnames="end0"
        echo "检测到end0和eth0，设置eth0为WAN，end0为LAN"
        
    elif [ $eth0_exists -eq 1 ] && [ $eth1_exists -eq 1 ]; then
        # eth0和eth1同时存在
        wan_ifname="eth1"
        lan_ifnames="eth0"
        echo "检测到eth0和eth1，设置eth1为WAN，eth0为LAN"
        
    else
        # 其他多网口情况，使用第一个接口作为WAN，其余作为LAN
        wan_ifname=$(echo "$ifnames" | awk '{print $1}')
        lan_ifnames=$(echo "$ifnames" | cut -d ' ' -f2-)
        echo "检测到多个网口，设置$wan_ifname为WAN，$lan_ifnames为LAN"
    fi
    
    # 设置WAN接口
    uci set network.wan=interface
    uci set network.wan.device="$wan_ifname"
    uci set network.wan.proto='dhcp'
    
    # 设置WAN6接口
    uci set network.wan6=interface
    uci set network.wan6.device="$wan_ifname"
    
    # 更新LAN接口成员
    section=$(uci show network | awk -F '[.=]' '/\.@?device\[\d+\]\.name=.br-lan.$/ {print $2; exit}')
    if [ -z "$section" ]; then
        echo "错误：找不到设备 'br-lan'"
    else
        # 删除原来的ports列表
        uci -q delete "network.$section.ports"
        # 添加新的ports列表
        for port in $lan_ifnames; do
            uci add_list "network.$section.ports"="$port"
        done
        echo "设备 'br-lan' 的端口已更新为: $lan_ifnames"
    fi
    
    # LAN口设置静态IP
    uci set network.lan.proto='static'
    uci set network.lan.ipaddr='192.168.100.1'
    uci set network.lan.netmask='255.255.255.0'
    
    uci commit network
fi

# 重启网络服务
echo "应用网络配置..."
/etc/init.d/network restart

# 设置所有网口可连接 SSH
uci set dropbear.@dropbear[0].Interface=''
uci commit

exit 0
