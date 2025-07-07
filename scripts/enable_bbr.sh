#!/bin/bash

# 检查是否为root用户
if [ "$(id -u)" != "0" ]; then
    echo "错误: 此脚本必须以root用户身份运行。"
    exit 1
fi

# 检查操作系统是否为Debian或Ubuntu
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$ID" != "debian" && "$ID" != "ubuntu" ]]; then
        echo "错误: 此脚本仅支持Debian或Ubuntu系统。"
        exit 1
    fi
else
    echo "错误: 无法识别的操作系统。"
    exit 1
fi

echo "正在检查内核版本..."
kernel_version=$(uname -r)
echo "当前内核版本: $kernel_version"

# 检查内核版本是否支持BBR (4.9及以上)
# 注意：Debian 9 (Stretch) 及以上版本通常自带4.9+内核
# Ubuntu 16.04.2 及以上版本通常自带4.9+内核
kernel_major=$(echo $kernel_version | cut -d'.' -f1)
kernel_minor=$(echo $kernel_version | cut -d'.' -f2)

if (( kernel_major < 4 )) || (( kernel_major == 4 && kernel_minor < 9 )); then
    echo "警告: 当前内核版本 ($kernel_version) 可能不支持BBR。建议升级内核到4.9或更高版本。"
    echo "如果您的内核版本低于4.9，BBR可能无法正常工作。"
    read -p "是否继续启用BBR (y/n)? " choice
    if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
        echo "操作已取消。"
        exit 0
    fi
fi

echo "正在启用BBR拥塞控制算法..."

# 备份sysctl配置
cp /etc/sysctl.conf /etc/sysctl.conf.bak
echo "已备份 /etc/sysctl.conf 到 /etc/sysctl.conf.bak"

# 添加或修改sysctl配置
# 确保net.core.default_qdisc=fq 和 net.ipv4.tcp_congestion_control=bbr
if grep -q "net.core.default_qdisc" /etc/sysctl.conf; then
    sed -i '/net.core.default_qdisc/c\net.core.default_qdisc=fq' /etc/sysctl.conf
else
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
fi

if grep -q "net.ipv4.tcp_congestion_control" /etc/sysctl.conf; then
    sed -i '/net.ipv4.tcp_congestion_control/c\net.ipv4.tcp_congestion_control=bbr' /etc/sysctl.conf
else
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
fi

# 应用sysctl配置
sysctl -p

echo "正在验证BBR是否已启用..."

# 验证net.ipv4.tcp_congestion_control是否为bbr
if sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
    echo "net.ipv4.tcp_congestion_control 已设置为 bbr."
else
    echo "错误: net.ipv4.tcp_congestion_control 未能设置为 bbr."
fi

# 验证tcp_bbr模块是否已加载
if lsmod | grep -q "tcp_bbr"; then
    echo "tcp_bbr 模块已加载."
else
    echo "错误: tcp_bbr 模块未加载。尝试加载模块..."
    modprobe tcp_bbr
    if lsmod | grep -q "tcp_bbr"; then
        echo "tcp_bbr 模块已成功加载."
    else
        echo "错误: 无法加载 tcp_bbr 模块。请检查内核是否支持BBR。"
    fi
fi

echo "BBR一键开启脚本执行完毕。请重启系统以确保所有更改生效。"
echo "您可以使用 'sysctl net.ipv4.tcp_congestion_control' 和 'lsmod | grep bbr' 来验证BBR状态。"