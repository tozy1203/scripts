#!/bin/bash

# ====================================================
# Debian/Ubuntu TCP 高性能自动化调优脚本 (增强版)
# 适用环境: Debian 10+, Ubuntu 18.04+ (内核需 > 4.9)
# ====================================================

# 1. 权限检查
if [ "$EUID" -ne 0 ]; then
    echo "错误：请以 root 权限运行此脚本 (sudo )"
    exit 1
fi

# 2. 内核版本检查 (BBR 至少需要 4.9)
KERNEL_MAJOR=$(uname -r | cut -d. -f1)
KERNEL_MINOR=$(uname -r | cut -d. -f2)
if [ "$KERNEL_MAJOR" -lt 4 ] || ([ "$KERNEL_MAJOR" -eq 4 ] && [ "$KERNEL_MINOR" -lt 9 ]); then
    echo "❌ 错误：当前内核版本 $(uname -r) 过低，不支持 BBR。"
    echo "请升级内核后再运行此脚本。"
    exit 1
fi

echo "--- 开始进行 TCP 网络参数调优 (增强版) ---"

# 3. 获取用户输入
read -p "请输入服务器带宽 (单位 Mbps, 例如 100): " BW
read -p "请输入典型往返延迟 (单位 ms, 例如 50 或 300): " RTT

# 4. 核心计算 (BDP 逻辑)
# BDP (Bytes) = (带宽 * 10^6 / 8) * (延迟 / 1000)
BDP=$(( BW * 1000000 / 8 * RTT / 1000 ))

# 基础缓冲区逻辑
MAX_BUF=$(( BDP * 4 ))
# 不低于 4MB 保证基础性能
if [ $MAX_BUF -lt 4194304 ]; then
    MAX_BUF=4194304
fi

# 5. 内存安全保护 (防止 BDP 计算过大导致 OOM)
TOTAL_MEM_KB=$(free -k | grep Mem | awk '{print $2}')
# 限制最大缓冲区不占用超过物理内存的 15%
MEM_LIMIT_BYTES=$(( TOTAL_MEM_KB * 1024 * 15 / 100 ))

if [ $MAX_BUF -gt $MEM_LIMIT_BYTES ]; then
    echo "⚠️ 警告：根据带宽计算的缓冲区超过内存限制，已自动调整为安全值。"
    MAX_BUF=$MEM_LIMIT_BYTES
fi

DEF_BUF=$BDP
# 默认值不低于 128KB，不高于 MAX_BUF
if [ $DEF_BUF -lt 131072 ]; then
    DEF_BUF=131072
fi
if [ $DEF_BUF -gt $MAX_BUF ]; then
    DEF_BUF=$MAX_BUF
fi

echo "------------------------------------------------"
echo "系统环境分析完毕："
echo "理论 BDP: $((BDP / 1024)) KB"
echo "系统最大缓冲区: $((MAX_BUF / 1024 / 1024)) MB"
echo "------------------------------------------------"

# 6. 创建优化配置文件
CONF_FILE="/etc/sysctl.d/99-network-optimization.conf"

cat << EOF > $CONF_FILE
# --- 拥塞控制优化 ---
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# --- 缓冲区限制优化 ---
net.core.rmem_max = $MAX_BUF
net.core.wmem_max = $MAX_BUF
net.ipv4.tcp_rmem = 4096 $DEF_BUF $MAX_BUF
net.ipv4.tcp_wmem = 4096 $DEF_BUF $MAX_BUF

# --- 高并发与快速响应优化 ---
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 20
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1

# --- 队列与并发连接数优化 ---
net.core.netdev_max_backlog = 10000
net.ipv4.tcp_max_syn_backlog = 8192
net.core.somaxconn = 4096
net.ipv4.tcp_syncookies = 1

# --- 保持连接活跃 (可选) ---
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3
EOF

# 7. 应用配置
sysctl --system > /dev/null

# 8. 验证结果
echo "------------------------------------------------"
echo "验证优化状态："
BBR_STATUS=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
if [ "$BBR_STATUS" == "bbr" ]; then
    echo "✅ BBR 拥塞算法启动成功"
else
    echo "❌ BBR 启动失败，请检查内核支持"
fi

# 检查队列算法
QDISC_STATUS=$(sysctl net.core.default_qdisc | awk '{print $3}')
if [ "$QDISC_STATUS" == "fq" ]; then
    echo "✅ FQ 队列调度已就绪"
fi

echo "✅ 优化参数已应用到: $CONF_FILE"
echo "💡 提示：此优化实时生效，重启后依然有效。"
echo "------------------------------------------------"
