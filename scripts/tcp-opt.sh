#!/bin/bash

# ====================================================
# TCP 智能全场景调优脚本 (V2.1 修复版)
# 适用场景：5G/长途公网/内网/高带宽 (通杀方案)
# 核心逻辑：动态 BDP 适配 + BBR + 防重传优化
# ====================================================

# 1. 权限检查
if [ "$EUID" -ne 0 ]; then
    echo "❌ 错误：请以 root 权限运行此脚本 (使用 sudo)"
    exit 1
fi

echo "--- 正在启动网络全场景智能调优 (高低延迟通用版) ---"

# 2. 获取输入（带默认值）
read -p "请输入服务器带宽 (Mbps, 默认 500): " BW
BW=${BW:-500}
read -p "请输入典型往返延迟 (ms, 默认 50): " RTT
RTT=${RTT:-50}

# 3. 核心计算 (修复 Bash 整数除法漏洞)
# 公式：BDP (Bytes) = (带宽 * 10^6 / 8) * (延迟 / 1000)
# 简化：BW * 125 * RTT
BDP=$(( BW * 125 * RTT ))

# 缓冲区策略：
# MAX_BUF 设置为 2 倍 BDP，既能跑满长途链路，又不会因为窗口过大导致低延迟下重传
MAX_BUF=$(( BDP * 2 ))

# 边界保护：
# 最小值 4MB (现代高速网络基础)
[ $MAX_BUF -lt 4194304 ] && MAX_BUF=4194304
# 最大值 64MB (防止极高延迟场景耗尽系统内存)
[ $MAX_BUF -gt 67108864 ] && MAX_BUF=67108864

# 默认值 (Default) 设为 BDP 的 1 倍（不低于 128KB）
DEF_BUF=$BDP
[ $DEF_BUF -lt 131072 ] && DEF_BUF=131072
[ $DEF_BUF -gt $MAX_BUF ] && DEF_BUF=$MAX_BUF

# 4. 内存安全检查 (防止 OOM)
TOTAL_MEM_KB=$(free -k | grep Mem | awk '{print $2}')
# 限制最大缓冲区不占用超过物理内存的 12%
MEM_LIMIT_BYTES=$(( TOTAL_MEM_KB * 1024 * 12 / 100 ))
if [ $MAX_BUF -gt $MEM_LIMIT_BYTES ]; then
    echo "⚠️ 警告：计算的缓冲区超过内存安全阈值，已锁定在 $((MEM_LIMIT_BYTES / 1024 / 1024)) MB"
    MAX_BUF=$MEM_LIMIT_BYTES
fi

echo "------------------------------------------------"
echo "系统分析完毕："
echo "理论 BDP: $((BDP / 1024)) KB"
echo "建议最大缓冲区上限: $((MAX_BUF / 1024 / 1024)) MB"
echo "建议默认窗口大小: $((DEF_BUF / 1024)) KB"
echo "------------------------------------------------"

# 5. 写入配置文件
CONF_FILE="/etc/sysctl.d/99-network-universal.conf"

cat << EOF > $CONF_FILE
# --- 拥塞算法与队列策略 ---
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# --- 缓冲区大小动态设置 (BDP 适配) ---
net.core.rmem_max = $MAX_BUF
net.core.wmem_max = $MAX_BUF
# rmem: min, default, max
net.ipv4.tcp_rmem = 4096 $DEF_BUF $MAX_BUF
# wmem: min, default, max
net.ipv4.tcp_wmem = 4096 16384 $MAX_BUF

# --- 核心延迟与防重传优化 ---
# 限制发送队列积压，防止低延迟网络下的 Bufferbloat (关键)
net.ipv4.tcp_notsent_lowat = 131072
# 强制开启低延迟模式
net.ipv4.tcp_low_latency = 1
# 禁用空闲后的慢启动，保持连接热度
net.ipv4.tcp_slow_start_after_idle = 0
# 开启 MTU 探测，解决长途网络 MTU 不一导致的丢包重传
net.ipv4.tcp_mtu_probing = 1

# --- 并发与回收优化 ---
net.core.somaxconn = 8192
net.core.netdev_max_backlog = 10000
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 25
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1

# --- 全局内存安全线 ---
net.ipv4.tcp_mem = $((TOTAL_MEM_KB/3)) $((TOTAL_MEM_KB/2)) $((TOTAL_MEM_KB*3/4))
EOF

# 6. 应用并验证
sysctl --system > /dev/null

echo "✅ 配置已生效！"
echo "当前拥塞控制算法: $(sysctl -n net.ipv4.tcp_congestion_control)"
echo "当前 FQ 队列状态: $(sysctl -n net.core.default_qdisc)"
echo "------------------------------------------------"
echo "💡 调优原理提示："
echo "1. 高延迟环境下，通过 $((MAX_BUF / 1024 / 1024))MB 窗口确保吞吐量。"
echo "2. 低延迟环境下，通过 tcp_notsent_lowat 机制有效压低重传率。"
echo "------------------------------------------------"
