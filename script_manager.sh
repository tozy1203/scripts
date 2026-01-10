#!/bin/bash

# 开启严格模式
set -euo pipefail

# 配置
GITHUB_RAW_BASE_URL="https://github.com/tozy1203/scripts/raw/refs/heads/main/scripts"

# 使用普通数组以保持固定显示顺序
# 格式: "名称|文件名"
SCRIPT_LIST=(
    "安装Caddy|caddy-install.sh"
    "安装aria2|install_aria2.sh"
    "安装ufw|install_ufw.sh"
    "安装openlist|install_openlist.sh"
    "安装sbox|sbox.sh"
    "tcp网络优化|tcp-opt.sh"
    "设置ipv4优先|ipv4-first.sh"
    "修改SSH端口|change_sshd_port.sh"
    "管理swap|swap.sh"
    "运行测速|sptest.sh"
)

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 错误处理：确保退出时删除临时文件
cleanup() {
    rm -f /tmp/remote_script_*.sh
}
trap cleanup EXIT

# 函数：检查必要的命令
check_dependencies() {
    for cmd in curl chmod; do
        if ! command -v "$cmd" &> /dev/null; then
            echo -e "${RED}错误：未找到命令 '$cmd'，请先安装。${NC}" >&2
            exit 1
        fi
    done
}

# 函数：打印标题
print_banner() {
    clear
    echo -e "${BLUE}====================================${NC}"
    echo -e "${BLUE}       远程脚本集成管理工具          ${NC}"
    echo -e "${BLUE}====================================${NC}"
}

# 函数：显示脚本列表
list_scripts() {
    echo -e "${YELLOW}可用的脚本列表：${NC}"
    for i in "${!SCRIPT_LIST[@]}"; do
        # 提取 "|" 前的描述部分
        local desc="${SCRIPT_LIST[$i]%%|*}"
        printf "%2d. %s\n" $((i + 1)) "$desc"
    done
    echo -e " q. 退出程序"
}

# 函数：执行选定的脚本
execute_script() {
    local index=$(( $1 - 1 ))
    # 获取文件名（提取 "|" 之后的部分）
    local script_name="${SCRIPT_LIST[$index]##*|}"
    local script_url="${GITHUB_RAW_BASE_URL}/${script_name}"
    local temp_script="/tmp/remote_script_${script_name}"

    echo -e "\n${BLUE}➜ 正在下载: ${NC}$script_name"
    
    # 下载脚本
    if curl -fsSL "$script_url" -o "$temp_script"; then
        echo -e "${GREEN}✓ 下载成功。正在启动...${NC}"
        echo -e "${YELLOW}------------------------------------${NC}"
        
        chmod +x "$temp_script"
        
        # 执行脚本，允许失败但不退出主程序
        if ! "$temp_script"; then
            echo -e "${RED}! 脚本执行过程中出现错误。${NC}"
        fi
        
        echo -e "${YELLOW}------------------------------------${NC}"
        read -n 1 -s -r -p "按任意键返回菜单..."
    else
        echo -e "${RED}✗ 错误：下载失败。请检查网络或 URL：${NC}\n$script_url"
        sleep 2
    fi
}

# --- 主程序逻辑 ---

check_dependencies

while true; do
    print_banner
    list_scripts
    echo
    read -p "请输入编号 [1-${#SCRIPT_LIST[@]}]: " user_choice

    case "$user_choice" in
        [qQ])
            echo -e "${GREEN}再见！${NC}"
            break
            ;;
        [0-9]*)
            # 校验数字范围
            if [[ "$user_choice" -ge 1 && "$user_choice" -le "${#SCRIPT_LIST[@]}" ]]; then
                execute_script "$user_choice"
            else
                echo -e "${RED}无效编号，请重新选择。${NC}"
                sleep 1
            fi
            ;;
        *)
            echo -e "${RED}输入错误，请输入数字或 q。${NC}"
            sleep 1
            ;;
    esac
done
