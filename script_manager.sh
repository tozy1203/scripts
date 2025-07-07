#!/bin/bash

GITHUB_RAW_BASE_URL="https://www.github.com/tozy1203/scripts/master/scripts"

# 函数：显示脚本列表
list_scripts() {
    echo "可用的脚本列表："
    local i=1
    # 假设脚本名称是固定的，或者可以通过某种方式获取
    # 这里我们直接列出已知的脚本名称
    local known_scripts=("caddy-install.sh" "sbox.sh" "sptest.sh")
    for script_name in "${known_scripts[@]}"; do
        echo "$i. $script_name"
        script_files[$i]="$script_name" # 存储脚本名称，而不是本地路径
        ((i++))
    done
    if [ ${#script_files[@]} -eq 0 ]; then
        echo "在 $SCRIPTS_DIR 目录中没有找到任何脚本。"
        exit 1
    fi
}

# 函数：执行选定的脚本
execute_script() {
    local choice=$1
    local script_name="${script_files[$choice]}"
    local script_url="${GITHUB_RAW_BASE_URL}/${script_name}"
    local temp_script="/tmp/${script_name}"

    if [ -n "$script_name" ]; then
        echo "正在从 $script_url 下载脚本..."
        if curl -sSL "$script_url" -o "$temp_script"; then
            echo "下载成功。正在执行脚本：$script_name"
            chmod +x "$temp_script"
            "$temp_script"
            rm "$temp_script" # 执行后删除临时文件
        else
            echo "错误：下载脚本失败。请检查网络连接或脚本URL。"
        fi
    else
        echo "无效的选择，请重新输入。"
    fi
}

# 主逻辑
declare -A script_files # 声明一个关联数组来存储脚本文件路径

list_scripts

while true; do
    read -p "请输入要执行的脚本编号 (输入 'q' 退出): " user_choice
    if [[ "$user_choice" == "q" ]]; then
        echo "退出脚本管理器。"
        break
    elif [[ "$user_choice" =~ ^[0-9]+$ ]] && [ -n "${script_files[$user_choice]}" ]; then
        execute_script "$user_choice"
    else
        echo "无效的输入，请输入有效的脚本编号或 'q' 退出。"
    fi
done