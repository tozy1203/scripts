#!/bin/bash
export LC_ALL=C
export LANG=en_US
export LANGUAGE=en_US.UTF-8


if [[ $(uname -m 2> /dev/null) != x86_64 ]]; then
    echo "请在x86_64架构的机器上运行此脚本。"
    exit 1
fi

uninstall() {
  $(which rm) -rf $1
  printf "已移除：%s\n" "$1"
}

set_caddy_systemd() {
  cat > "/etc/systemd/system/caddy.service" <<-EOF
[Unit]
Description=Caddy
Documentation=https://caddyserver.com/docs/
After=network.target network-online.target
Requires=network-online.target

[Service]
#User=caddy
#Group=caddy
User=root
Group=root
ExecStart=/usr/bin/caddy run --environ --config /etc/caddy/Caddyfile
ExecReload=/usr/bin/caddy reload --config /etc/caddy/Caddyfile
TimeoutStopSec=5s
#LimitNOFILE=1048576
#LimitNPROC=512
PrivateTmp=true
ProtectSystem=full
#AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF
}

get_caddy() {
  if [ ! -f "/usr/bin/caddy" ]; then # 检查 /usr/bin/caddy 文件是否存在，而不是目录
    echo "Caddy 2 未安装，开始安装。"
    local caddy_link="https://github.com/tozy1203/scripts/raw/refs/heads/main/files/caddy.zip" # 更改为 .zip

    $(which mkdir) -p "/etc/caddy"
    printf "已创建：%s\n" "/etc/caddy"

    # 使用 unzip 解压
    wget "${caddy_link}" -O /tmp/caddy.zip && $(which unzip) -o /tmp/caddy.zip -d /usr/bin/ && $(which chmod) +x /usr/bin/caddy
    printf "已安装：%s\n" "/usr/bin/caddy"


    echo "正在构建 caddy.service 文件。"
    set_caddy_systemd

    systemctl daemon-reload
    systemctl enable caddy

    echo "Caddy 2 已安装。"
  fi
}

install_caddy(){
    get_caddy
}

uninstall_caddy(){
  if [ -f "/usr/bin/caddy" ]; then
  echo "正在关闭 Caddy 服务。"
  systemctl stop caddy
  systemctl disable caddy
  uninstall /etc/systemd/system/caddy.service
  echo  "正在移除 Caddy 二进制文件及相关文件。"
  uninstall /usr/bin/caddy
  uninstall /etc/caddy
  echo  "Caddy 已成功移除。"
fi
}

action=$1
[ -z "$1" ] && action=install
case "$action" in
    install|uninstall)
        ${action}_caddy
        ;;
    *)
        echo "参数错误！[${action}]"
        echo "用法：$(basename "$0") [install|uninstall]"
        ;;
esac
