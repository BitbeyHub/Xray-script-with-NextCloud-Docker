#!/bin/bash

## First we define some functional printing colors
green()                            #原谅绿
{
	echo -e "\\033[32;1m${*}\\033[0m"
}
yellow()                           #鸭屎黄
{
	echo -e "\\033[33;1m${*}\\033[0m"
}
red()                              #爆闪姨妈红
{
	echo -e "\\033[5;41;34m${*}\\033[0m"
}


## Parse input arguments
if [[ $# -eq 0 ]]; then
	red "此脚本必须带参数运行"
	exit 1
fi
while [[ $# -ge 2 ]]; do
	case $1 in
		'--ssl-domain')
			shift
			if [[ -z $1 ]] || [[ $1 == -* ]]; then
				red "此脚本至少需要一个解析到本服务器的域名\n请补充域名后重新运行脚本！形如hostname.yr.domain\n如需同时指定多个SSL域名，使用+相连即可，例如 hn1.yr.domain+hn2.yr.domain"
				exit 1
			else
				sslDomain="$1"
				if [[ $sslDomain == *+* ]]; then
					sslDomain=`echo $sslDomain | sed 's/+/ /g'`
				fi
				green "您输入的域名是：${sslDomain}"
			fi
			shift
		;;

		'--fake-domain')
			shift
			if [[ -z $1 ]] || [[ $1 == -* ]]; then
				red "选择反向代理伪装网站，需要填写一个http网址！"
				exit 1
			else
				fakeUrl="$1"
				green "您输入的反向代理伪装网址是：${fakeUrl}"
			fi
			shift
		;;
	esac
done

if ! [[ -v sslDomain && -v fakeUrl ]]; then
	red "指向域名和伪装域名都是必需的！"
	exit 1
fi

## Manage BBR status
version_ge()
{
	test "$(echo -e "$1\\n$2" | sort -rV | head -n 1)" == "$1"
}

yellow "正在获取最新版本内核版本号。。。。"
your_kernel_version="$(uname -r | cut -d - -f 1)"
green "你的内核版本号是$your_kernel_version"

if version_ge $your_kernel_version 4.9; then
	yellow "正在启用bbr。。。。。。"

	if [ "$(sysctl net.ipv4.tcp_congestion_control | cut -d = -f 2 | awk '{print $1}')" == "bbr" ] && [ "$(grep '^[ '$'\t]*net.ipv4.tcp_congestion_control[ '$'\t]*=' "/etc/sysctl.conf" | tail -n 1 | cut -d = -f 2 | awk '{print $1}')" == "bbr" ] && [ "$(sysctl net.core.default_qdisc | cut -d = -f 2 | awk '{print $1}')" == "$(grep '^[ '$'\t]*net.core.default_qdisc[ '$'\t]*=' "/etc/sysctl.conf" | tail -n 1 | cut -d = -f 2 | awk '{print $1}')" ]; then
		green "--------------------bbr已启用--------------------"
	else
		sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
		sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
		echo 'net.core.default_qdisc = fq' >> /etc/sysctl.conf
		echo 'net.ipv4.tcp_congestion_control = bbr' >> /etc/sysctl.conf
		sysctl -p
		sleep 1s

		if [ "$(sysctl net.ipv4.tcp_congestion_control | cut -d = -f 2 | awk '{print $1}')" == "bbr" ] && [ "$(sysctl net.core.default_qdisc | cut -d = -f 2 | awk '{print $1}')" == "fq" ]; then
			green "--------------------bbr已启用--------------------"
		else
			red "bbr安装失败"
		fi
	fi
else
	red "内核版本号$your_kernel_version过低，不支持bbr"
fi



## Install X-ray service and finish its config
path="/$(head -c 20 /dev/urandom | md5sum | head -c 16)"
xid_ws="$(cat /proc/sys/kernel/random/uuid)"
# xid_2="$(cat /proc/sys/kernel/random/uuid)"
# xid_3="$(cat /proc/sys/kernel/random/uuid)"

yellow "正在安装Xray。。。。。。"
if ! bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root --without-logfiles && ! bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root --without-logfiles; then
	red    "安装Xray失败"
	exit 1
else
	cat > /usr/local/etc/xray/config.json << EOF
{
	"inbounds": [
		{
			"sniffing": {
				"enabled": true
			},
			"listen": "@/virtualpath/xray/ws.sock",
			"protocol": "vless",
			"settings": {
				"clients": [
					{
						"id": "$xid_ws"
					}
				],
				"decryption": "none"
			},
			"streamSettings": {
				"network": "ws",
				"wsSettings": {
					"path": "$path"
				}
			}
		}
	],
	"routing": {
		"rules": [
			{
				"type": "field",
				"protocol": ["bittorrent"],
				"outboundTag": "blocked"
			}
		]
	},
	"outbounds": [
		{
			"protocol": "freedom"
		},
		{
			"protocol": "blackhole",
			"tag": "blocked"
		}
	]
}
EOF
	systemctl restart xray
	if [ $(systemctl is-active xray) == active ];then
		green "--------------------Xray已安装--------------------"
	else
		red "xray因未知原因安装失败"
		exit 1
	fi
fi



## Install Caddy reverse proxy server
# assume this is Debian/Ubuntu and use apt as package manager
yellow "正在部署Caddy。。。。。。"

if version_ge 6 $your_kernel_version; then
	apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
	curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
	curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
	# Borrowed from https://caddyserver.com/docs/install#debian-ubuntu-raspbian
fi
apt update -qq && apt install -y caddy

cat > /etc/caddy/Caddyfile << EOF
$sslDomain {
	reverse_proxy $path unix/@/virtualpath/xray/ws.sock

	reverse_proxy * $fakeUrl {
		header_up Host {upstream_hostport}
		header_up -X-Forwarded-*
	}
}
EOF

systemctl restart caddy
if [ $(systemctl is-active caddy) == active ];then
	green "--------------------Caddy已部署--------------------"
else
	red "Caddy因未知原因安装失败"
	exit 1
fi


## Showing key parameters for client config
echo "uuid: $xid_ws"
echo "wspath: $path"
