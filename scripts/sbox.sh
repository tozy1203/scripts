#!/bin/bash

check_singbox_installed() {
    if command -v sing-box &> /dev/null; then
        echo "sing-box 已安装"
        return 0
    else
        echo "sing-box 未安装"
        return 1
    fi
}

install() {

echo "安装sbox"
curl -LO https://github.com/SagerNet/sing-box/releases/download/v1.12.1/sing-box_1.12.1_linux_amd64.deb && dpkg -i sing-box_1.12.1_linux_amd64.deb
systemctl enable sing-box && systemctl daemon-reload

}

restart() {
echo "重启sbox"
systemctl restart sing-box
}

viewclient() {
cat /etc/sing-box/client.outs
}

main() {
read -p "输入直连域名: " host  
echo "直连host为: $host"

read -p "输入cdn host(回车为直链域名): " cdnHost
    cdnHost=${cdnHost:-$host}
echo "cdnHost为: $cdnHost"

read -p "输入httpupgrade path（回车随机）: " path
    path=${path:-$(cat /dev/urandom | tr -dc 'a-z' | fold -w 5 | head -n 1)}
echo "httpupgrade path为: $path"

read -p "输入acme路径(默认/root/.local/share/caddy): " acmeRoot 
    acmeRoot=${acmeRoot:-"/root/.local/share/caddy"}
echo "acme路径为: $acmeRoot"

echo "生成uuid"
uuid=$(sing-box generate uuid)
sspwd=$(sing-box generate rand --base64 16)

echo "生成reality密钥对"
keypair=$(sing-box generate reality-keypair)
pkey=$(echo "$keypair" | grep "PrivateKey:" | awk '{print $2}')
pukey=$(echo "$keypair" | grep "PublicKey:" | awk '{print $2}')

echo "生成short_id"
sid=$(sing-box generate rand --hex 8)

cat > /etc/sing-box/config.json <<EOF
{
    "inbounds": [
        {
            "type": "vless",
            "listen": "::",
            "listen_port": 8080,
            "users": [
                {
                    "uuid": "$uuid",
                    "flow": ""
                }
            ],
            "transport": {
                "type": "httpupgrade",
                "path": "/$path"
            },
            "multiplex": {
                "enabled": true
            }
        },
        {
            "type": "anytls",
            "listen": "::",
            "listen_port": 8443,
            "users": [
                {
                    "password": "$uuid",
                    "name": "xtls-rprx-vision"
                }
            ],
            "tls": {
                "enabled": true,
                "server_name": "$host",
                "reality": {
                    "enabled": true,
                    "handshake": {
                        "server": "$host",
                        "server_port": 443
                    },
                    "private_key": "$pkey",
                    "short_id": [
                        "$sid"
                    ]
                }
            }
        },
        {
            "type": "shadowsocks",
            "tag": "ss-in",
            "listen": "127.0.0.1",
            "listen_port": 5353,
            "tcp_fast_open": true,
            "method": "2022-blake3-aes-128-gcm",
            "password": "$sspwd",
            "multiplex": {
                "enabled": true
            }
        },
        {
            "type": "hysteria2",
            "tag": "hy2-in",
            "listen": "::",
            "listen_port": 443,
            "users": [
                {
                    "name": "1",
                    "password": "$uuid"
                }
            ],
            "ignore_client_bandwidth": false,
            "tls": {
                "enabled": true,
                "server_name": "$host",
                "acme": {
                    "domain": [
                        "$host"
                    ],
                    "data_directory": "$acmeRoot",
                    "default_server_name": "$host",
                    "disable_http_challenge": true,
                    "disable_tls_alpn_challenge": true
                }
            },
            "masquerade": "http://127.0.0.1",
            "brutal_debug": false
        }
    ],
    "outbounds": [
        {
            "type": "direct"
        }
    ]
}
EOF

cat > /etc/sing-box/client.outs <<EOF
套cdn：
vless://$uuid@ip.sb:80/?type=httpupgrade&encryption=none&host=$cdnHost&path=%2F$path#httpupgrade-$cdnHost
hy2://$uuid@$host:443/?sni=$host#hy2-$host

出站json：
{
	"type": "vless",
	"tag": "$cdnHost.cdn",
	"server": "ip.sb",
	"server_port": 80,
	"uuid": "$uuid",
	"transport": {
		"type": "httpupgrade",
		"path": "/$path",
		"Host": "$cdnHost"
	}
},
{
	"type": "shadowsocks",
	"tag": "$cdnHost.ss",
	"server": "127.0.0.1",
	"server_port": 5353,
	"method": "2022-blake3-aes-128-gcm",
	"password": "$sspwd",
	"multiplex": {
		"enabled": true,
		"max_connections": 8,
		"min_streams": 4,
		"padding": true,
		"protocol": "smux"
	},
	"detour": "$cdnHost.cdn"
},
{
	"type": "hysteria2",
	"tag": "$host.hy2",
	"server": "$host",
	"server_port": 443,
	"up_mbps": 10,
	"down_mbps": 100,
	"password": "$uuid",
	"tls": {
		"enabled": true,
		"server_name": "$host"
	},
	"brutal_debug": false
},
{
	"type": "anytls",
	"tag": "$host.anytls",
	"server": "$host",
	"server_port": 8443,
	"password": "$uuid",
	"tls": {
		"enabled": true,
		"server_name": "$host",
		"utls": {
			"enabled": true,
			"fingerprint": "chrome"
		},
		"reality": {
			"enabled": true,
			"public_key": "$pukey",
			"short_id": "$sid"
		}
	}
}
EOF

viewclient
restart
}

menu() {
check_singbox_installed
while true; do
    echo "请选择一个选项:"
        echo "1. 全新安装"
        echo "2. 更新"
        echo "3. 查看客户端配置"
        echo "4. 退出"
    read choice

    case $choice in
        1)
            install
            main
            ;;
        2)
            install
            restart
            ;;
        3)
            viewclient
            ;;
        4)
            echo "退出程序"
            exit 0
        ;;
        *)
            echo "无效的选项，请重新选择："
            ;;
    esac
done
}

menu