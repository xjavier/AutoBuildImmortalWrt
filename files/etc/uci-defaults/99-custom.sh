#!/bin/sh
# 99-custom.sh 固定6网口布局
# 1-3号口 eth0 eth1 eth2  → br-lan
# 4-5号口 eth3 eth4        → br-iptv  169.254.10.10/24
# 6号口   eth5             → WAN
LOGFILE="/etc/config/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >>$LOGFILE

# 防火墙默认放行WAN入口
uci set firewall.@zone[1].input='ACCEPT'

# 安卓电视时间服务器
uci add dhcp domain
uci set "dhcp.@domain[-1].name=time.android.com"
uci set "dhcp.@domain[-1].ip=203.107.6.88"

# PPPoE配置
SETTINGS_FILE="/etc/config/pppoe-settings"
if [ -f "$SETTINGS_FILE" ]; then
    . "$SETTINGS_FILE"
fi

# ====================== 固定网口 ======================
lan_ifnames="eth0 eth1 eth2"
iptv_ifnames="eth3 eth4"
wan_ifname="eth5"
# ======================================================

# 清空旧网络配置
uci -q delete network.br-iptv
uci -q delete network.iptv
uci commit network

# ====================== 创建 br-iptv 网桥 ======================
# 强制创建网桥设备
uci set network.br-iptv=device
uci set network.br-iptv.type='bridge'
uci set network.br-iptv.name='br-iptv'

# 添加端口：eth3 eth4
for port in $iptv_ifnames; do
    uci add_list network.br-iptv.ports="$port"
done

# 创建iptv接口
uci set network.iptv=interface
uci set network.iptv.device='br-iptv'
uci set network.iptv.proto='static'
uci set network.iptv.ipaddr='169.254.10.10'
uci set network.iptv.netmask='255.255.255.0'
uci set network.iptv.auto='1'

echo "✅ br-iptv 已创建，端口：$iptv_ifnames" >>$LOGFILE

# ====================== LAN 配置 ======================
# 配置 br-lan
sec=$(uci show network | awk '/device.*br-lan/ {print $2}' | head -n1)
if [ -n "$sec" ]; then
    uci -q delete network.$sec.ports
    for p in $lan_ifnames; do
        uci add_list network.$sec.ports="$p"
    done
fi

# LAN IP
uci set network.lan.proto='static'
uci set network.lan.netmask='255.255.255.0'
IP_FILE="/etc/config/custom_router_ip.txt"
if [ -f "$IP_FILE" ]; then
    uci set network.lan.ipaddr="$(cat $IP_FILE)"
else
    uci set network.lan.ipaddr='192.168.100.1'
fi

# ====================== WAN 配置 ======================
uci set network.wan=interface
uci set network.wan.device="$wan_ifname"
uci set network.wan.proto='dhcp'

uci set network.wan6=interface
uci set network.wan6.device="$wan_ifname"
uci set network.wan6.proto='dhcpv6'

# PPPoE
if [ "$enable_pppoe" = "yes" ]; then
    uci set network.wan.proto='pppoe'
    uci set network.wan.username="$pppoe_account"
    uci set network.wan.password="$pppoe_password"
    uci set network.wan.peerdns='1'
    uci set network.wan6.proto='none'
fi

# 保存网络
uci commit network

# ====================== 防火墙：IPTV区域 ======================
uci -q delete firewall.iptv
uci set firewall.iptv=zone
uci set firewall.iptv.name='iptv'
uci set firewall.iptv.network='iptv'
uci set firewall.iptv.input='ACCEPT'
uci set firewall.iptv.output='ACCEPT'
uci set firewall.iptv.forward='REJECT'

# 你要的防火墙规则：允许IPTV UDP进路由器
uci add firewall rule
uci set firewall.@rule[-1].name='Allow_IPTV_UDP_to_Router'
uci set firewall.@rule[-1].src='iptv'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].target='ACCEPT'
uci set firewall.@rule[-1].family='any'
uci set firewall.@rule[-1].direction='in'

uci commit firewall

# ====================== Docker ======================
if command -v dockerd >/dev/null; then
FW=/etc/config/firewall
uci delete firewall.docker 2>/dev/null
for i in $(uci show firewall | grep forwarding | cut -d'[' -f2 | cut -d']' -f1 | sort -rn); do
uci delete firewall.@forwarding[$i] 2>/dev/null
done
uci commit firewall
cat >> "$FW" << EOF

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
fi

# ====================== 安全与服务 ======================
uci delete ttyd.@ttyd[0].interface 2>/dev/null
uci set dropbear.@dropbear[0].Interface=''
uci commit

# 作者信息
sed -i "s/DISTRIB_DESCRIPTION='[^']*'/DISTRIB_DESCRIPTION='Packaged by wukongdaily'/" /etc/openwrt_release

# 修复zsh
if opkg list-installed | grep -q luci-app-advancedplus; then
sed -i '/\/usr\/bin\/zsh/d' /etc/profile
sed -i '/zsh/d' /etc/init.d/advancedplus 2>/dev/null
fi

exit 0
