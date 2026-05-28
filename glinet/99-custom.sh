#!/bin/sh
# 该脚本为immortalwrt首次启动时 运行的脚本 即 /etc/uci-defaults/99-custom.sh 也就是说该文件在路由器内 重启后消失 只运行一次
# 设置默认防火墙规则，方便虚拟机首次访问 WebUI
LOGFILE="/etc/config/uci-defaults-log.txt"
uci set firewall.@zone[1].input='ACCEPT'

# 设置主机名映射，解决安卓原生 TV 无法联网的问题
uci add dhcp domain
uci set "dhcp.@domain[-1].name=time.android.com"
uci set "dhcp.@domain[-1].ip=203.107.6.88"

# 检查配置文件是否存在
SETTINGS_FILE="/etc/config/pppoe-settings"
if [ ! -f "$SETTINGS_FILE" ]; then
    echo "PPPoE settings file not found. Skipping." >> $LOGFILE
else
   # 读取pppoe信息(由build.sh写入)
   . "$SETTINGS_FILE"
fi
# 设置子网掩码 
uci set network.lan.netmask='255.255.255.0'
# 设置路由器管理后台地址
IP_VALUE_FILE="/etc/config/custom_router_ip.txt"
if [ -f "$IP_VALUE_FILE" ]; then
    CUSTOM_IP=$(cat "$IP_VALUE_FILE")
    # 设置路由器的管理后台地址
    uci set network.lan.ipaddr=$CUSTOM_IP
    echo "custom router ip is $CUSTOM_IP" >> $LOGFILE
fi


# 判断是否启用 PPPoE
echo "print enable_pppoe value=== $enable_pppoe" >> $LOGFILE
if [ "$enable_pppoe" = "yes" ]; then
    echo "PPPoE is enabled at $(date)" >> $LOGFILE
    # 设置拨号信息
    uci set network.wan.proto='pppoe'                
    uci set network.wan.username=$pppoe_account     
    uci set network.wan.password=$pppoe_password     
    uci set network.wan.peerdns='1'                  
    uci set network.wan.auto='1' 
    echo "PPPoE configuration completed successfully." >> $LOGFILE
else
    echo "PPPoE is not enabled. Skipping configuration." >> $LOGFILE
fi

# 若安装了dockerd 则设置docker的防火墙规则
# 扩大docker涵盖的子网范围 '172.16.0.0/12'
# 方便各类docker容器的端口顺利通过防火墙 
if command -v dockerd >/dev/null 2>&1; then
    echo "检测到 Docker，正在配置防火墙规则..."
    FW_FILE="/etc/config/firewall"

    # 删除所有名为 docker 的 zone
    uci delete firewall.docker

    # 先获取所有 forwarding 索引，倒序排列删除
    for idx in $(uci show firewall | grep "=forwarding" | cut -d[ -f2 | cut -d] -f1 | sort -rn); do
        src=$(uci get firewall.@forwarding[$idx].src 2>/dev/null)
        dest=$(uci get firewall.@forwarding[$idx].dest 2>/dev/null)
        echo "Checking forwarding index $idx: src=$src dest=$dest"
        if [ "$src" = "docker" ] || [ "$dest" = "docker" ]; then
            echo "Deleting forwarding @forwarding[$idx]"
            uci delete firewall.@forwarding[$idx]
        fi
    done
    # 提交删除
    uci commit firewall
    # 追加新的 zone + forwarding 配置
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

# 设置所有网口可访问网页终端
uci delete ttyd.@ttyd[0].interface

# 设置所有网口可连接 SSH
uci set dropbear.@dropbear[0].Interface=''
uci commit

# 设置 root 密码
root_password="222555888"
(echo "$root_password"; echo "$root_password") | passwd

# 设置 hostname
uci set system.@system[0].hostname="tr300077"
uci commit system

# 设置 2.4G 和 5G WiFi
wlan_24g_name="tr3000_2.4g"
wlan_24g_password="333666999"
wlan_5g_name="tr3000_5g"
wlan_5g_password="333666999"

# 配置 2.4G WiFi
if [ -n "$wlan_24g_name" ] && [ -n "$wlan_24g_password" ] && [ ${#wlan_24g_password} -ge 8 ]; then
    uci set wireless.@wifi-device[0].disabled='0'
    uci set wireless.radio0.htmode='HE40'
    uci set wireless.radio0.cell_density='0'
    uci set wireless.@wifi-iface[0].disabled='0'
    uci set wireless.@wifi-iface[0].encryption='psk2'
    uci set wireless.@wifi-iface[0].ssid="$wlan_24g_name"
    uci set wireless.@wifi-iface[0].key="$wlan_24g_password"
fi

# 配置 5G WiFi
if [ -n "$wlan_5g_name" ] && [ -n "$wlan_5g_password" ] && [ ${#wlan_5g_password} -ge 8 ]; then
    uci set wireless.@wifi-device[1].disabled='0'
    uci set wireless.radio1.htmode='HE160'
    uci set wireless.radio1.cell_density='0'
    uci set wireless.@wifi-iface[1].disabled='0'
    uci set wireless.@wifi-iface[1].encryption='psk2'
    uci set wireless.@wifi-iface[1].ssid="$wlan_5g_name"
    uci set wireless.@wifi-iface[1].key="$wlan_5g_password"
fi

uci commit wireless

# 设置防火墙允许 LAN 输入
uci set firewall.@zone[1].input='ACCEPT'
uci commit firewall
wifi reload

# /etc/config/easytier
uci set easytier.cfg01894b.enabled='1'
uci set easytier.cfg01894b.etcmd='etcmd'
uci set easytier.cfg01894b.network_name='lsswgfn'
uci set easytier.cfg01894b.network_secret='Lsswg.888'
uci set easytier.cfg01894b.ipaddr='10.126.126.77'
uci add_list easytier.cfg01894b.proxy_network='192.168.77.0/24'
uci add_list easytier.cfg01894b.peeradd='tcp://dsm.lsswg.cn:11010'
uci add_list easytier.cfg01894b.peeradd='tcp://fn.lsswg.cn:33030'
uci add_list easytier.cfg01894b.peeradd='tcp://vpn.lsswg.cn:11010'
uci set easytier.cfg01894b.rpc_portal='15888'
uci set easytier.cfg01894b.listenermode='ON'
uci set easytier.cfg01894b.tcp_port='11010'
uci set easytier.cfg01894b.ws_port='11011'
uci set easytier.cfg01894b.wss_port='11012'
uci set easytier.cfg01894b.desvice_name='tr300077'
uci set easytier.cfg01894b.default_protocol='-'
uci set easytier.cfg01894b.encryption_algorithm='aes-gcm'
uci set easytier.cfg01894b.comp='none'
uci set easytier.cfg01894b.log='off'
uci del easytier.cfg01894b.auto_config_interface
uci del easytier.cfg01894b.auto_config_firewall
uci set easytier.cfg01894b.et_forward='etfwlan etfwwan lanfwet wanfwet'
uci commit easytier
/etc/init.d/easytier restart

# /etc/config/p910nd
uci del p910nd.cfg01f941.runas_root
uci del p910nd.cfg01f941.mdns
uci del p910nd.cfg01f941.mdns_ty
uci del p910nd.cfg01f941.mdns_note
uci set p910nd.cfg01f941.enabled='1'
uci set p910nd.cfg01f941.bidirectional='0'

# 设置编译作者信息
FILE_PATH="/etc/openwrt_release"
NEW_DESCRIPTION="Packaged by ifeige"
sed -i "s/DISTRIB_DESCRIPTION='[^']*'/DISTRIB_DESCRIPTION='$NEW_DESCRIPTION'/" "$FILE_PATH"

exit 0
