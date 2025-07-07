#!/bin/bash

# 设置脚本在遇到错误时立即退出
set -e
# 设置管道中的任何命令失败时脚本立即退出
set -o pipefail

# 函数：在 Debian/Ubuntu 上安装 Speedtest CLI
安装测速工具_Debian() {
    echo "正在安装 Speedtest CLI 到 Debian/Ubuntu..."
    # 更新软件包列表
    apt update || { echo "错误：apt update 失败，请检查网络或软件源。"; exit 1; }
    # 安装 curl 工具
    apt install -y curl || { echo "错误：安装 curl 失败。"; exit 1; }
    echo "正在添加 Ookla Speedtest 软件源..."
    # 添加 Speedtest 官方软件源
    curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | bash || { echo "错误：添加 Speedtest 软件源失败。"; exit 1; }
    echo "正在安装 Speedtest CLI 包..."
    # 安装 speedtest 包
    apt install -y speedtest || { echo "错误：安装 speedtest 失败。"; exit 1; }
    echo "Speedtest CLI 已成功安装到 Debian/Ubuntu。"
}

# 函数：在 CentOS/RHEL 上安装 Speedtest CLI
安装测速工具_CentOS() {
    echo "正在安装 Speedtest CLI 到 CentOS/RHEL..."
    echo "正在添加 Ookla Speedtest 软件源..."
    # 添加 Speedtest 官方软件源
    curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.rpm.sh | bash || { echo "错误：添加 Speedtest 软件源失败。"; exit 1; }
    echo "正在清理 yum 缓存并重新生成缓存..."
    # 清理并重新生成 yum 缓存，确保新的软件源生效
    yum clean all || { echo "错误：yum clean all 失败。"; exit 1; }
    yum makecache || { echo "错误：yum makecache 失败。"; exit 1; }
    echo "正在安装 Speedtest CLI 包..."
    # 安装 speedtest 包
    yum install -y speedtest || { echo "错误：安装 speedtest 失败。"; exit 1; }
    echo "Speedtest CLI 已成功安装到 CentOS/RHEL。"
}

# 函数：卸载 Speedtest CLI
卸载测速工具() {
    echo "正在尝试卸载 Speedtest CLI..."
    if [ -f "/etc/debian_version" ]; then
        echo "检测到 Debian/Ubuntu 系统。"
        local repo_file="/etc/apt/sources.list.d/ookla_speedtest-cli.list"
        if [ -f "$repo_file" ]; then
            echo "正在移除 Speedtest 软件源文件: $repo_file"
            rm "$repo_file"
        fi
        echo "正在卸载 speedtest 包..."
        apt remove -y speedtest || { echo "警告：卸载 speedtest 失败，可能未安装。"; }
        echo "Speedtest CLI 已从 Debian/Ubuntu 卸载或未安装。"
        elif [ -f "/etc/redhat-release" ]; then
        echo "检测到 CentOS/RHEL 系统。"
        local repo_file="/etc/yum.repos.d/ookla_speedtest-cli.repo"
        if [ -f "$repo_file" ]; then
            echo "正在移除 Speedtest 软件源文件: $repo_file"
            rm "$repo_file"
        fi
        echo "正在卸载 speedtest 包..."
        yum remove -y speedtest || { echo "警告：卸载 speedtest 失败，可能未安装。"; }
        echo "Speedtest CLI 已从 CentOS/RHEL 卸载或未安装。"
    else
        echo -e "\033[31m错误：不支持的操作系统。\033[0m"
            exit 1
        fi
}

# 主逻辑
if [[ "$1" == "-u" ]]; then
    # 如果参数是 -u，则执行卸载操作
    卸载测速工具
    echo -e "\033[0;32m卸载完成或未安装。--- 状态：[成功]\033[0m"
elif [[ -z "$1" || "$1" == "-i" ]]; then
    # 如果没有参数或参数是 -i，则执行安装并运行操作
    if command -v speedtest >/dev/null 2>&1; then
        echo "Speedtest 已安装。正在运行测速..."
        # 自动接受许可协议并运行测速
        yes | speedtest || { echo "错误：运行 speedtest 失败。"; exit 1; }
    else
        echo "Speedtest 未安装。正在尝试安装..."
        if [ -f "/etc/debian_version" ]; then
            安装测速工具_Debian
            echo "正在运行测速..."
            yes | speedtest || { echo "错误：运行 speedtest 失败。"; exit 1; }
        elif [ -f "/etc/redhat-release" ]; then
            安装测速工具_CentOS
            echo "正在运行测速..."
            yes | speedtest || { echo "错误：运行 speedtest 失败。"; exit 1; }
        else
            echo -e "\033[31m错误：本脚本仅支持 Debian/Ubuntu 和 CentOS/RHEL。\033[0m"
            exit 1
    fi
fi
else
    # 处理无效参数
    echo -e "\033[31m错误：无效参数。用法：$0 [-u | -i]\033[0m"
    echo -e "\033[36m  -u: 卸载 Speedtest CLI\033[0m"
    echo -e "\033[36m  -i: 安装并运行 Speedtest CLI (默认)\033[0m"
    exit 1
fi
