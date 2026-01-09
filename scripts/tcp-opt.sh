#!/bin/bash

# ====================================================
# Debian TCP 高性能调优脚本 (支持高延迟与常规延迟)
# 适用环境: Debian 10/11/12, Ubuntu 18.04+
# ====================================================

# 1. 权限检查
if [ "$EUID" -ne 0 ]; then
    echo "错误：请以 root 权限运行此脚本 (sudo ./tcp_speed.sh)"
    exit 1
fi

echo "--- 开始进行 TCP 网络参数调优 ---"

# 2. 获取用户输入
read -p "请输入服务器带宽 (单位 Mbps, 例如 100): " BW
read -p "请输入典型往返延迟 (单位 ms, 例如 50 或 300): " RTT

# 3. 核心计算 (BDP 逻辑)
# BDP (Bytes) = (带宽 * 10^6 / 8) * (延迟 / 1000)
BDP=$(( BW * 1000000 / 8 * RTT / 1000 ))

# 最大缓冲区设置为 BDP 的 4 倍，且不低于 4MB 以保证基础性能
MAX_BUF=$(( BDP * 4 ))
if [ $MAX_BUF -lt 4194304 ]; then
    MAX_BUF=4194304
fi

# 默认起步值设置为 BDP 的 1 倍，不低于 128KB
DEF_BUF=$BDP
if [ $DEF_BUF -lt 131072 ]; then
    DEF_BUF=131072
fi

echo "------------------------------------------------"
echo "根据您的环境 ($BW Mbps, $RTT ms) 优化如下："
echo "理论 BDP: $((BDP / 1024)) KB"
echo "系统最大缓冲区: $((MAX_BUF / 1024 / 1024)) MB"
echo "------------------------------------------------"

# 4. 创建优化配置文件
# 采用 .d 目录管理，不破坏系统原始 sysctl.conf
CONF_FILE="/etc/sysctl.d/99-network-optimization.conf"

cat << EOF > $CONF_FILE
# --- 拥塞控制优化 ---
# 强制开启 BBR，在高延迟和丢包环境下效果最佳
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# --- 缓冲区限制优化 ---
# 全局最大内存限制
net.core.rmem_max = $MAX_BUF
net.core.wmem_max = $MAX_BUF
# TCP 读缓冲区: [最小, 初始默认, 最大]
net.ipv4.tcp_rmem = 4096 $DEF_BUF $MAX_BUF
# TCP 写缓冲区: [最小, 初始默认, 最大]
net.ipv4.tcp_wmem = 4096 $DEF_BUF $MAX_BUF

# --- 高并发与快速响应优化 ---
# 开启窗口缩放 (必须开启以支持大缓冲区)
net.ipv4.tcp_window_scaling = 1
# 开启选择性确认 (优化丢包重传)
net.ipv4.tcp_sack = 1
# 开启 TCP Fast Open (减少握手延迟)
net.ipv4.tcp_fastopen = 3
# 允许 TIME_WAIT 状态的端口重用 (解决高并发端口耗尽)
net.ipv4.tcp_tw_reuse = 1
# 连接断开后的超时时间
net.ipv4.tcp_fin_timeout = 20
# 禁用空闲后的慢启动 (保持长连接的活跃速度)
net.ipv4.tcp_slow_start_after_idle = 0

# --- 队列与防攻击优化 ---
# 增大网卡积压队列
net.core.netdev_max_backlog = 10000
# 增大半连接队列
net.ipv4.tcp_max_syn_backlog = 8192
# 开启 SYN Cookies 防止洪水攻击
net.ipv4.tcp_syncookies = 1
EOF

# 5. 应用配置
sysctl --system

# 6. 验证结果
echo "------------------------------------------------"
echo "验证优化状态："
BBR_STATUS=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
if [ "$BBR_STATUS" == "bbr" ]; then
    echo "✅ BBR 拥塞算法启动成功"
else
    echo "❌ BBR 启动失败，请检查内核版本 (需 > 4.9)"
fi

echo "✅ 优化参数已保存至: $CONF_FILE"
echo "提示：如果效果不理想，可以直接删除该文件并运行 'sysctl --system' 还原。"
