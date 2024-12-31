#!/bin/bash

echo "编译固件大小为: $PROFILE MB"

# 输出调试信息
echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始编译..."



# 定义所需安装的包列表
PACKAGES=""
PACKAGES="$PACKAGES curl"
PACKAGES="$PACKAGES luci-i18n-diskman-zh-cn"
PACKAGES="$PACKAGES luci-i18n-firewall-zh-cn"
PACKAGES="$PACKAGES luci-i18n-filebrowser-zh-cn"
PACKAGES="$PACKAGES luci-app-argon-config"
PACKAGES="$PACKAGES luci-i18n-argon-config-zh-cn"
PACKAGES="$PACKAGES luci-i18n-opkg-zh-cn"
PACKAGES="$PACKAGES luci-i18n-ttyd-zh-cn"
PACKAGES="$PACKAGES luci-i18n-passwall-zh-cn"
PACKAGES="$PACKAGES luci-app-openclash"
PACKAGES="$PACKAGES luci-i18n-homeproxy-zh-cn"
PACKAGES="$PACKAGES openssh-sftp-server"
PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"
PACKAGES="$PACKAGES luci-i18n-ddns-go-zh-cn"
PACKAGES="$PACKAGES ddns-go"
PACKAGES="$PACKAGES acme"
PACKAGES="$PACKAGES acme-acmesh"
PACKAGES="$PACKAGES acme-acmesh-dnsapi"
PACKAGES="$PACKAGES acme-common"
PACKAGES="$PACKAGES luci-i18n-acme-zh-cn"
PACKAGES="$PACKAGES etherwake"
PACKAGES="$PACKAGES luci-i18n-wol-zh-cn"
PACKAGES="$PACKAGES netdata"
PACKAGES="$PACKAGES luci-i18n-netdata-zh-cn"
PACKAGES="$PACKAGES uhttpd"
PACKAGES="$PACKAGES uhttpd-mod-ubus"
PACKAGES="$PACKAGES luci-i18n-uhttpd-zh-cn"
PACKAGES="$PACKAGES luci-ssl-openssl"
PACKAGES="$PACKAGES luci-i18n-upnp-zh-cn"
PACKAGES="$PACKAGES miniupnpd-nftables"
PACKAGES="$PACKAGES luci-i18n-autoreboot-zh-cn"
PACKAGES="$PACKAGES zerotier"
PACKAGES="$PACKAGES luci-i18n-zerotier-zh-cn"

# 构建镜像
echo "$(date '+%Y-%m-%d %H:%M:%S') - Building image with the following packages:"
echo "$PACKAGES"

make image PROFILE="generic" PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files" ROOTFS_PARTSIZE=$PROFILE

if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Build failed!"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - Build completed successfully."
