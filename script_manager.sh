#!/bin/bash

set -euo pipefail

GITHUB_RAW_BASE_URL="https://github.com/tozy1203/scripts/raw/refs/heads/main/scripts"

# 声明一个关联数组，用于存储脚本的简介名称和对应的文件名
declare -A script_descriptions
script_descriptions["安装Caddy"]="caddy-install.sh"
script_descriptions["安装sbox"]="sbox.sh"
script_descriptions["运行测速"]="sptest.sh"
# 声明一个关联数组，用于存储用户选择的序号和对应的文件名
declare -A script_choices

# 函数：检查必要的命令
check_dependencies() {
    if ! command -v curl &> /dev/null; then
        echo "错误：'curl' 命令未找到。请先安装 curl。" >&2
        exit 1
    fi
}

# 函数：显示脚本列表
list_scripts() {
    echo "可用的脚本列表："
    local i=1
    if [ ${#script_descriptions[@]} -eq 0 ]; then
        echo "没有找到任何可用的脚本信息。请检查脚本配置。"
        exit 1
    fi

    for description in "${!script_descriptions[@]}"; do
        echo "$i. $description"
        script_choices[$i]="${script_descriptions[$description]}" # 存储序号到文件名
        ((i++))
    done
}

# 函数：执行选定的脚本
execute_script() {
    local choice=$1
    local script_name="${script_choices[$choice]}" # 从 script_choices 获取文件名
    local script_url="${GITHUB_RAW_BASE_URL}/${script_name}"
    local temp_script="/tmp/${script_name}"

    if [ -n "$script_name" ]; then
        echo "正在从 $script_url 下载脚本..."
        if curl -fSLo "$temp_script" "$script_url"; then
            echo "下载成功。正在执行脚本：$script_name"
            chmod +x "$temp_script"
            if "$temp_script"; then
                echo "脚本 $script_name 执行完成。"
            else
                echo "警告：脚本 $script_name 执行失败或以非零状态码退出。"
            fi
            rm "$temp_script" # 执行后删除临时文件
        else
            echo "错误：下载脚本失败。请检查网络连接、脚本URL或GitHub仓库是否存在。"
        fi
    else
        echo "无效的选择，未找到对应的脚本。"
    fi
}

# 主逻辑
check_dependencies

list_scripts

while true; do
    read -p "请输入要执行的脚本编号 (输入 'q' 退出): " user_choice
    case "$user_choice" in
        q|Q)
            echo "退出脚本管理器。"
            break
            ;;
        [0-9]*)
            if [ -n "${script_choices[$user_choice]}" ]; then
                execute_script "$user_choice"
            else
                echo "无效的脚本编号。请重新输入。"
            fi
            ;;
        *)
            echo "无效的输入，请输入有效的脚本编号或 'q' 退出。"
            ;;
    esac
done
