#!/bin/bash

# 检查是否以 root 权限运行
if [[ $EUID -ne 0 ]]; then
   echo "错误：此脚本必须以 root 权限运行。"
   exit 1
fi

show_menu() {
    echo "=============================="
    echo "   Debian Swap 管理工具"
    echo "=============================="
    echo "1) 查看当前 Swap 状态"
    echo "2) 创建/扩容 Swap 文件"
    echo "3) 禁用并删除所有 Swap 文件"
    echo "4) 释放 Swap 缓存 (Swapoff & Swapon)"
    echo "5) 退出"
    echo "=============================="
    read -p "请选择操作 [1-5]: " choice
}

view_swap() {
    echo "--- 当前内存与 Swap 使用情况 ---"
    free -h
    echo ""
    echo "--- Swap 分区/文件详情 ---"
    swapon --show
}

add_swap() {
    read -p "请输入要创建的 Swap 大小 (例如 2G, 4G, 512M): " swap_size
    swap_file="/swapfile"

    # 如果已存在，先禁用
    if [ -f "$swap_file" ]; then
        echo "检测到已有 $swap_file，正在更新..."
        swapoff "$swap_file" 2>/dev/null
        rm -f "$swap_file"
    fi

    echo "正在创建 $swap_size 的 Swap 文件..."
    fallocate -l "$swap_size" "$swap_file" || dd if=/dev/zero of="$swap_file" bs=1M count=$(echo "$swap_size" | sed 's/[^0-9]//g')
    
    chmod 600 "$swap_file"
    mkswap "$swap_file"
    swapon "$swap_file"

    # 写入 /etc/fstab 实现开机自启
    if ! grep -q "$swap_file" /etc/fstab; then
        echo "$swap_file none swap sw 0 0" >> /etc/fstab
    fi

    echo "Swap 创建成功！"
    view_swap
}

remove_swap() {
    read -p "确定要禁用并删除所有 Swap 文件吗？(y/n): " confirm
    if [ "$confirm" == "y" ]; then
        swapoff -a
        sed -i '/swap/d' /etc/fstab
        # 尝试删除根目录下常见的 swapfile
        if [ -f "/swapfile" ]; then
            rm -f "/swapfile"
        fi
        echo "所有 Swap 已禁用并从 /etc/fstab 中移除。"
    else
        echo "操作取消。"
    fi
}

flush_swap() {
    echo "正在将 Swap 数据写回内存 (这可能需要一点时间)..."
    swapoff -a && swapon -a
    echo "Swap 缓存已释放。"
}

while true; do
    show_menu
    case $choice in
        1) view_swap ;;
        2) add_swap ;;
        3) remove_swap ;;
        4) flush_swap ;;
        5) exit 0 ;;
        *) echo "无效选项，请重新输入。" ;;
    esac
    echo ""
done
