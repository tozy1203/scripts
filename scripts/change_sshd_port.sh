#!/bin/bash

# 检查是否以 root 用户运行
if [ "$(id -u)" -ne 0 ]; then
    echo "此脚本需要以 root 用户权限运行。"
    echo "请使用 sudo 运行：sudo $0"
    exit 1
fi

SSHD_CONFIG="/etc/ssh/sshd_config"
BACKUP_DIR="/etc/ssh/backup"
TIMESTAMP=$(date +%Y%m%d%H%M%S)
BACKUP_FILE="$BACKUP_DIR/sshd_config.bak.$TIMESTAMP"

echo "--- 修改 SSHD 端口脚本 ---"

# 提示用户输入新的 SSH 端口
read -p "请输入新的 SSH 端口 (例如: 2222): " NEW_PORT

# 验证端口是否为有效数字
if ! [[ "$NEW_PORT" =~ ^[0-9]+$ ]] || [ "$NEW_PORT" -le 1024 ] || [ "$NEW_PORT" -gt 65535 ]; then
    echo "错误: 无效的端口号。端口必须是 1025 到 65535 之间的数字。"
    exit 1
fi

echo "正在备份 SSHD 配置文件..."
mkdir -p "$BACKUP_DIR"
cp "$SSHD_CONFIG" "$BACKUP_FILE"
if [ $? -eq 0 ]; then
    echo "配置文件已备份到: $BACKUP_FILE"
else
    echo "错误: 备份配置文件失败。请检查权限或路径。"
    exit 1
fi

echo "正在修改 SSHD 配置文件..."

# 使用 sed 修改 Port 行，如果不存在则添加
if grep -q "^Port" "$SSHD_CONFIG"; then
    sed -i "s/^Port .*/Port $NEW_PORT/" "$SSHD_CONFIG"
else
    # 如果没有 Port 行，则在文件末尾添加
    echo "Port $NEW_PORT" >> "$SSHD_CONFIG"
fi

# 确保 PermitRootLogin 和 PasswordAuthentication 设置正确
sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin yes/' "$SSHD_CONFIG"
sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication yes/' "$SSHD_CONFIG"

if [ $? -eq 0 ]; then
    echo "SSHD 配置文件已更新，新端口为: $NEW_PORT"
else
    echo "错误: 修改 SSHD 配置文件失败。"
    exit 1
fi

echo "正在重新启动 SSHD 服务..."
# 尝试使用 systemctl 或 service 重新启动服务
if command -v systemctl &> /dev/null; then
    systemctl restart sshd
elif command -v service &> /dev/null; then
    service sshd restart
else
    echo "警告: 无法找到 systemctl 或 service 命令。请手动重新启动 SSHD 服务。"
fi

if [ $? -eq 0 ]; then
    echo "SSHD 服务已重新启动。"
    echo "重要: 请确保您的防火墙已允许新端口 ($NEW_PORT) 的连接。"
    echo "例如，对于 UFW: sudo ufw allow $NEW_PORT/tcp"
    echo "对于 firewalld: sudo firewall-cmd --permanent --add-port=$NEW_PORT/tcp && sudo firewall-cmd --reload"
    echo "请勿关闭当前 SSH 会话，直到您通过新端口成功连接！"
else
    echo "错误: 重新启动 SSHD 服务失败。请检查日志或手动重新启动。"
    exit 1
fi

echo "脚本执行完毕。"