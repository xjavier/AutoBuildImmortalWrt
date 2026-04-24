#!/bin/sh
# 99-custom.sh 固定6网口布局（强制创建 br-iptv 版）
# 1-3号口 eth0 eth1 eth2  → br-lan 局域网
# 4-5号口 eth3 eth4        → br-iptv  静态 169.254.10.10/24
# 6号口   eth5             → WAN
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
if [ -f "$SETTINGS_FILE" ]; then
    . "$SETTINGS_FILE"
fi

# ====================== 固定网口定义 ======================
lan_ifnames="eth0 eth1 eth2"
iptv_ifnames="eth3 eth4"
wan_ifname="eth5"
echo "固定网口规划：WAN=$wan_ifname | LAN=$lan_ifnames | IPTV=$iptv_ifnames" >>$LOGFILE
# ==========================================================

# --------------------------
# 1. 强制创建 br-iptv 网桥配置（直接写文件，绕过UCI索引问题）
# --------------------------
echo "
config device 'br-iptv'
    option name 'br-iptv'
    option type 'bridge'
    list ports '$iptv_ifnames'

config interface 'iptv'
    option device 'br-iptv'
    option proto 'static'
    option ipaddr '169.254.10.10'
    option netmask '255.255.255.0'
    option auto '1'
" >> /etc/config/network

echo "✅ br-iptv 配置已直接写入 network 文件" >>$LOGFILE

# --------------------------
# 2. 配置 br-lan 网桥端口
# --------------------------
section=$(uci show network | awk -F '[.=]' '/\.@?device\[\d+\]\.name=.br-lan.$/ {print $2; exit}')
if [ -n "$section" ]; then
    uci -q delete "network.$section.ports"
    for port in $lan_ifnames; do
        uci add_list "network.$section.ports"="$port"
    done
    echo "Updated br-lan ports: $lan_ifnames" >>$LOGFILE
fi

# --------------------------
# 3. LAN静态IP设置
# --------------------------
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

# --------------------------
# 4. 配置 WAN & WAN6
# --------------------------
uci set network.wan=interface
uci set network.wan.device="$wan_ifname"
uci set network.wan.proto='dhcp'

uci set network.wan6=interface
uci set network.wan6.device="$wan_ifname"
uci set network.wan6.proto='dhcpv6'

# --------------------------
# 5. PPPoE拨号配置
# --------------------------
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

# 保存网络配置
uci commit network

# --------------------------
# 6. 防火墙：IPTV区域 + 你要的UDP规则
# --------------------------
uci -q delete firewall.iptv
uci set firewall.iptv=zone
uci set firewall.iptv.name='iptv'
uci set firewall.iptv.network='iptv'
uci set firewall.iptv.input='ACCEPT'
uci set firewall.iptv.output='ACCEPT'
uci set firewall.iptv.forward='REJECT'

# 你要的规则：允许IPTV的UDP流量进入路由器
uci add firewall rule
uci set firewall.@rule[-1].name='Allow_IPTV_UDP_to_Router'
uci set firewall.@rule[-1].src='iptv'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].target='ACCEPT'
uci set firewall.@rule[-1].family='any'
uci set firewall.@rule[-1].direction='in'

uci commit firewall

# --------------------------
# 7. Docker 防火墙规则
# --------------------------
if command -v dockerd >/dev/null 2>&1; then
    echo "检测到 Docker，正在配置防火墙规则..."
    FW_FILE="/etc/config/firewall"

    uci delete firewall.docker 2>/dev/null

    # 删除旧的docker转发规则
    for idx in $(uci show firewall | grep "=forwarding" | cut -d[ -f2 | cut -d] -f1 | sort -rn); do
        src=$(uci get firewall.@forwarding[$idx].src 2>/dev/null)
        dest=$(uci get firewall.@forwarding[$idx].dest 2>/dev/null)
        if [ "$src" = "docker" ] || [ "$dest" = "docker" ]; then
            uci delete firewall.@forwarding[$idx] 2>/dev/null
        fi
    done
    uci commit firewall

    # 写入新的docker防火墙配置
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

# --------------------------
# 8. 所有网口开放SSH和网页终端
# --------------------------
uci delete ttyd.@ttyd[0].interface 2>/dev/null
uci set dropbear.@dropbear[0].Interface=''
uci commit

# --------------------------
# 9. 设置编译作者信息
# --------------------------
FILE_PATH="/etc/openwrt_release"
NEW_DESCRIPTION="Packaged by wukongdaily"
sed -i "s/DISTRIB_DESCRIPTION='[^']*'/DISTRIB_DESCRIPTION='$NEW_DESCRIPTION'/" "$FILE_PATH"

# --------------------------
# 10. 修复 advancedplus zsh 报错
# --------------------------
if opkg list-installed | grep -q '^luci-app-advancedplus '; then
    sed -i '/\/usr\/bin\/zsh/d' /etc/profile
    sed -i '/\/bin\/zsh/d' /etc/init.d/advancedplus 2>/dev/null
    sed -i '/\/usr\/bin\/zsh/d' /etc/init.d/advancedplus 2>/dev/null
fi

exit 0
