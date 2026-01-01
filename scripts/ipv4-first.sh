#!/bin/bash

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then 
  echo "请使用 sudo 或 root 账号运行此脚本"
  exit 1
fi

FILE="/etc/gai.conf"
TARGET_LINE="precedence ::ffff:0:0/96  100"

echo "正在设置 IPv4 优先级高于 IPv6..."

# 1. 检查文件中是否已经有取消注释的配置
if grep -q "^precedence ::ffff:0:0/96  100" "$FILE"; then
    echo "配置已存在，无需修改。"
else
    # 2. 如果有被注释的行，则取消注释
    if grep -q "#precedence ::ffff:0:0/96  100" "$FILE"; then
        sed -i 's/#precedence ::ffff:0:0\/96  100/precedence ::ffff:0:0\/96  100/' "$FILE"
        echo "已取消注释 IPv4 优先配置。"
    # 3. 如果完全没有这一行，则追加到文件末尾
    else
        echo "precedence ::ffff:0:0/96  100" >> "$FILE"
        echo "已添加 IPv4 优先配置到文件末尾。"
    fi
fi


echo "设置完成！"
