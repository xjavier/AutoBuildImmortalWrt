#!/bin/sh
# 99-custom.sh 固定6网口布局
# 1-3号口 eth0 eth1 eth2  → br-lan 局域网
# 4-5号口 eth3 eth4        → br-iptv  静态 169.254.10.10/24
# 6号口   eth5             → WAN
# Log file for debugging
LOGFILE="/etc/config/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >>$LOGFILE

# 设置默认防火墙规则，方便虚拟机首次访问 WebUI
uci set firewall.@zone[1].input='ACCEPT'

# 设置主机名映射，解决安卓原生 TV 无法联网的问题
uci add dhcp domain
uci set "dhcp.@domain[-1].name=time.android.com"
uci set "dhcp.@domain[-1].ip=203.107.6.88"

# 检查pppoe配置文件
SETTINGS_FILE="/etc/config/pppoe-settings"
if [ ! -f "$SETTINGS_FILE" ]; then
    echo "PPPoE settings file not found. Skipping." >>$LOGFILE
else
    . "$SETTINGS_FILE"
fi

# ====================== 固定6网口定义 ======================
lan_ifnames="eth0 eth1 eth2"
iptv_ifnames="eth3 eth4"
wan_ifname="eth5"
echo "固定网口规划：WAN=$wan_ifname | LAN=$lan_ifnames | IPTV=$iptv_ifnames" >>$LOGFILE
# ==========================================================

# 配置 WAN & WAN6
uci set network.wan=interface
uci set network.wan.device="$wan_ifname"
uci set network.wan.proto='dhcp'

uci set network.wan6=interface
uci set network.wan6.device="$wan_ifname"
uci set network.wan6.proto='dhcpv6'

# 配置 br-lan 网桥端口
section=$(uci show network | awk -F '[.=]' '/\.@?device\[\d+\]\.name=.br-lan.$/ {print $2; exit}')
if [ -z "$section" ]; then
    echo "error：cannot find device 'br-lan'." >>$LOGFILE
else
    uci -q delete "network.$section.ports"
    for port in $lan_ifnames; do
        uci add_list "network.$section.ports"="$port"
    done
    echo "Updated br-lan ports: $lan_ifnames" >>$LOGFILE
fi

# LAN静态IP设置
uci set network.lan.proto='static'
uci set network.lan.netmask='255.255.255.0'
IP_VALUE_FILE="/etc/config/custom_router_ip.txt"
if [ -f "$IP_VALUE_FILE" ]; then
    CUSTOM_IP=$(cat "$IP_VALUE_FILE")
    uci set network.lan.ipaddr=$CUSTOM_IP
    echo "custom router ip is $CUSTOM_IP" >> $LOGFILE
else
    uci set network.lan.ipaddr='192.168.100.1'
    echo "default router ip is 192.168.100.1" >> $LOGFILE
fi

# ========== 新建 br-iptv 网桥 + 静态IP 169.254.10.10/24 ==========
uci -q delete network.br-iptv
uci -q delete network.iptv

# 创建IPTV网桥
uci set network.br-iptv=device
uci set network.br-iptv.type='bridge'
uci set network.br-iptv.name='br-iptv'
for port in $iptv_ifnames; do
    uci add_list network.br-iptv.ports="$port"
done

# IPTV接口配置静态地址
uci set network.iptv=interface
uci set network.iptv.device='br-iptv'
uci set network.iptv.proto='static'
uci set network.iptv.ipaddr='169.254.10.10'
uci set network.iptv.netmask='255.255.255.0'
uci set network.iptv.auto='1'
echo "Created br-iptv ports: $iptv_ifnames , IPTV IP:169.254.10.10/24" >>$LOGFILE

# PPPoE拨号配置
echo "enable_pppoe value: $enable_pppoe" >>$LOGFILE
if [ "$enable_pppoe" = "yes" ]; then
    echo "PPPoE enabled, configuring..." >>$LOGFILE
    uci set network.wan.proto='pppoe'
    uci set network.wan.username="$pppoe_account"
    uci set network.wan.password="$pppoe_password"
    uci set network.wan.peerdns='1'
    uci set network.wan.auto='1'
    uci set network.wan6.proto='none'
    echo "PPPoE config done." >>$LOGFILE
else
    echo "PPPoE not enabled." >>$LOGFILE
fi

uci commit network

# ========== 新增IPTV独立防火墙区域 ==========
uci -q delete firewall.iptv
uci set firewall.iptv=zone
uci set firewall.iptv.name='iptv'
uci set firewall.iptv.input='ACCEPT'
uci set firewall.iptv.output='ACCEPT'
uci set firewall.iptv.forward='REJECT'
uci add_list firewall.iptv.network='iptv'

# ========== 新增你要的IPTV UDP 入站规则 ==========
uci -q delete firewall.allow_iptv_udp_to_router
uci add firewall rule
uci set firewall.@rule[-1].name='Allow_IPTV_UDP_to_Router'
uci set firewall.@rule[-1].src='iptv'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].target='ACCEPT'
uci set firewall.@rule[-1].family='any'
uci set firewall.@rule[-1].direction='in'

uci commit firewall

# Docker 防火墙规则
if command -v dockerd >/dev/null 2>&1; then
    echo "检测到 Docker，正在配置防火墙规则..."
    FW_FILE="/etc/config/firewall"

    uci delete firewall.docker

    for idx in $(uci show firewall | grep "=forwarding" | cut -d[ -f2 | cut -d] -f1 | sort -rn); do
        src=$(uci get firewall.@forwarding[$idx].src 2>/dev/null)
        dest=$(uci get firewall.@forwarding[$idx].dest 2>/dev/null)
        if [ "$src" = "docker" ] || [ "$dest" = "docker" ]; then
            uci delete firewall.@forwarding[$idx]
        fi
    done
    uci commit firewall
    cat <<EOF >>"$FW_FILE"

config zone 'docker'
  option input 'ACCEPT'
  option output 'ACCEPT'
  option forward 'ACCEPT'
  option name 'docker'
  list subnet '172.16.0.0/12'

config forwarding
  option src 'docker'
  option dest 'lan'

config forwarding
  option src 'docker'
  option dest 'wan'

config forwarding
  option src 'lan'
  option dest 'docker'
EOF

else
    echo "未检测到 Docker，跳过防火墙配置。"
fi

# 所有网口可访问网页终端
uci delete ttyd.@ttyd[0].interface

# 所有网口可连接 SSH
uci set dropbear.@dropbear[0].Interface=''
uci commit

# 设置编译作者信息
FILE_PATH="/etc/openwrt_release"
NEW_DESCRIPTION="Packaged by xj2vier"
sed -i "s/DISTRIB_DESCRIPTION='[^']*'/DISTRIB_DESCRIPTION='$NEW_DESCRIPTION'/" "$FILE_PATH"

# 修复 advancedplus zsh 报错
if opkg list-installed | grep -q '^luci-app-advancedplus '; then
    sed -i '/\/usr\/bin\/zsh/d' /etc/profile
    sed -i '/\/bin\/zsh/d' /etc/init.d/advancedplus
    sed -i '/\/usr\/bin\/zsh/d' /etc/init.d/advancedplus
fi

exit 0
