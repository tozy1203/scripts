#!/bin/bash

# 检查是否以 root 用户运行
if [ "$(id -u)" -ne 0 ]; then
    echo "此脚本需要以 root 用户权限运行。"
    echo "请使用 sudo 运行：sudo $0"
    exit 1
fi

# 函数：在 Debian/Ubuntu 上安装 UFW
安装ufw_Debian() {
    echo "正在安装 UFW 到 Debian/Ubuntu..."
    # 更新软件包列表
    apt update || { echo "错误：apt update 失败，请检查网络或软件源。"; exit 1; }
    # 安装 ufw 工具
    apt install -y ufw || { echo "错误：安装 ufw 失败。"; exit 1; }
    echo "UFW 已成功安装到 Debian/Ubuntu。"
}

# 函数：在 CentOS/RHEL 上安装 UFW
安装ufw_CentOS() {
    echo "正在安装 UFW 到 CentOS/RHEL..."
    # 安装 ufw 工具
    yum install -y ufw || { echo "错误：安装 ufw 失败。"; exit 1; }
    echo "UFW 已成功安装到 CentOS/RHEL。"
}

# 函数：配置 UFW 防火墙规则
配置ufw() {
    echo "正在配置 UFW 防火墙规则..."

    # 从 SSHD 配置文件中读取 SSH 端口
    SSH_PORT=$(grep ^Port /etc/ssh/sshd_config | awk '{print $2}')

    # 检查是否成功读取 SSH 端口，如果失败则默认为 22
    if [ -z "$SSH_PORT" ]; then
        SSH_PORT=22
        echo "无法从 SSHD 配置文件中读取端口，使用默认端口 22。"
    fi

    # 允许 SSH 连接
    ufw allow "$SSH_PORT"/tcp || { echo "错误：允许 SSH 连接失败。"; exit 1; }

    # 允许 80 端口 (HTTP)
    ufw allow 80/tcp || { echo "错误：允许 80 端口失败。"; exit 1; }

    # 允许 443 端口 (HTTPS)
    ufw allow 443/tcp || { echo "错误：允许 443 端口失败。"; exit 1; }

    # 启用 UFW
    ufw enable || { echo "错误：启用 UFW 失败。"; exit 1; }

    echo "UFW 防火墙规则已配置。"
}

# 检测操作系统类型
if [ -f /etc/debian_version ]; then
    # Debian 或 Ubuntu 系统
    安装ufw_Debian
    配置ufw
elif [ -f /etc/redhat-release ]; then
    # CentOS 或 RHEL 系统
    安装ufw_CentOS
    配置ufw
else
    echo "不支持的操作系统。"
    exit 1
fi

echo "脚本执行完毕。"