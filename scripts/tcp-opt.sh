#!/bin/bash

# ====================================================
# TCP 低延迟高性能自动化调优脚本 (V2.0 强化版)
# 针对：低延迟、防缓冲区膨胀、防过度重传
# ====================================================

# 1. 权限检查
if [ "$EUID" -ne 0 ]; then
    echo "❌ 错误：请以 root 权限运行此脚本 (sudo ./script.sh)"
    exit 1
fi

# 2. 内核版本检查
KERNEL_VER=$(uname -r | cut -d. -f1,2)
if (( $(echo "$KERNEL_VER < 4.9" | bc -l) )); then
    echo "❌ 错误：内核版本 $KERNEL_VER 过低，不支持 BBR，请升级内核。"
    exit 1
fi

echo "--- 正在启动网络深度调优方案 ---"

# 3. 获取用户输入
read -p "请输入服务器带宽 (单位 Mbps, 例如 1000): " BW
read -p "请输入典型往返延迟 (单位 ms, 例如 50): " RTT

# 4. 核心计算 (BDP 逻辑)
# BDP = (带宽 * 10^6 / 8) * (延迟 / 1000)
BDP=$(( BW * 1000000 / 8 * RTT / 1000 ))

# 缓冲区策略：
# MAX_BUF 设置为 2 倍 BDP (足够撑满带宽，同时防止 Bufferbloat)
# 针对低延迟场景，不建议设置 4 倍那么大，2 倍是平衡重传和吞吐的黄金值。
MAX_BUF=$(( BDP * 2 ))

# 兜底逻辑：不低于 4MB，不高于 32MB (除非是非常特殊的超长肥管道)
[ $MAX_BUF -lt 4194304 ] && MAX_BUF=4194304
[ $MAX_BUF -gt 33554432 ] && MAX_BUF=33554432

# 5. 内存安全保护 (根据总内存动态限制)
TOTAL_MEM_KB=$(free -k | grep Mem | awk '{print $2}')
# 限制单个连接缓冲区最大不占用超过物理内存的 10%
MEM_LIMIT_BYTES=$(( TOTAL_MEM_KB * 1024 * 10 / 100 ))
[ $MAX_BUF -gt $MEM_LIMIT_BYTES ] && MAX_BUF=$MEM_LIMIT_BYTES

# 默认发送窗口建议设为 BDP 的 1 倍
DEF_BUF=$BDP
[ $DEF_BUF -lt 131072 ] && DEF_BUF=131072
[ $DEF_BUF -gt $MAX_BUF ] && DEF_BUF=$MAX_BUF

echo "------------------------------------------------"
echo "计算结果："
echo "理论 BDP: $((BDP / 1024)) KB"
echo "建议最大缓冲区: $((MAX_BUF / 1024 / 1024)) MB"
echo "------------------------------------------------"

# 6. 写入配置文件
CONF_FILE="/etc/sysctl.d/99-network-low-latency.conf"

cat << EOF > $CONF_FILE
# --- 拥塞算法与队列 (核心) ---
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# --- 缓冲区大小设置 (基于 BDP 计算) ---
net.core.rmem_max = $MAX_BUF
net.core.wmem_max = $MAX_BUF
net.ipv4.tcp_rmem = 4096 131072 $MAX_BUF
net.ipv4.tcp_wmem = 4096 16384 $MAX_BUF

# --- 针对“重传”与“延迟”的专项优化 ---
# 限制尚未发送的数据在队列中的大小，极大地缓解缓冲区膨胀导致的重传和延迟
net.ipv4.tcp_notsent_lowat = 131072
# 开启低延迟模式
net.ipv4.tcp_low_latency = 1
# 禁用空闲后的慢启动，避免连接断续时速度骤降
net.ipv4.tcp_slow_start_after_idle = 0
# 开启 MTU 探测，防止因中间路径分片导致的丢包重传
net.ipv4.tcp_mtu_probing = 1

# --- 快速连接与并发优化 ---
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 25
net.core.somaxconn = 8192
net.ipv4.tcp_max_syn_backlog = 8192
net.core.netdev_max_backlog = 10000
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1

# --- 内存水位线 (防止高并发下内存溢出) ---
# 参考系统总内存自动调整
net.ipv4.tcp_mem = $((TOTAL_MEM_KB/3)) $((TOTAL_MEM_KB/2)) $((TOTAL_MEM_KB*3/4))
EOF

# 7. 应用配置
sysctl --system > /dev/null

# 8. 验证
echo "✅ 优化已应用！"
echo "当前拥塞控制: $(sysctl -n net.ipv4.tcp_congestion_control)"
echo "当前最大缓冲区: $(( $(sysctl -n net.core.rmem_max) / 1024 / 1024 )) MB"
echo "当前 notsent_lowat (防膨胀限制): $(sysctl -n net.ipv4.tcp_notsent_lowat) Bytes"
