#!/bin/bash

# ====================================================
# TCP 智能全场景调优脚本 (V4.1 手动精准版)
# 特性：基于手动输入 RTT 计算 BDP、解决起步慢瓶颈
# ====================================================

# 确保以 root 权限运行
if [ "$EUID" -ne 0 ]; then
    echo "❌ 错误：请以 root 权限运行 (sudo ./script.sh)"
    exit 1
fi

echo "------------------------------------------------"
echo "⚙️  正在启动网络环境参数匹配..."

# 1. 获取用户输入
read -p "请输入服务器带宽 (Mbps, 默认 300): " BW
BW=${BW:-300}

read -p "请输入典型往返延迟 (ms, 默认 50): " RTT
RTT=${RTT:-50}

# 2. 核心计算：带宽延迟积 (BDP)
# 逻辑：BDP (Bytes) = [带宽(Mbps) * 125,000] * [延迟(ms) / 1000]
BDP=$(( BW * RTT * 125 ))

# 3. 场景智能分类与策略选择
if [ "$RTT" -lt 100 ]; then
    # --- 低延迟场景策略 (<100ms) ---
    SCENE="低延迟模式 (快速响应)"
    MAX_BUF=$(( BDP * 2 ))           # 给予 2 倍冗余应对突发
    NOTSENT_LIMIT=65536              # 严格限制内核积压 (64KB)
    REORDERING=3                     
    [ $MAX_BUF -lt 4194304 ] && MAX_BUF=4194304 # 最小 4MB
else
    # --- 中高延迟场景策略 (>=100ms) ---
    SCENE="中高延迟模式 (吞吐优先)"
    MAX_BUF=$(( BDP * 3 / 2 ))       # 1.5 倍 BDP 确保长管道填满
    NOTSENT_LIMIT=262144             # 放宽积压限制 (256KB)
    REORDERING=20                    # 提高乱序容忍度
    [ $MAX_BUF -lt 8388608 ] && MAX_BUF=8388608 # 最小 8MB
fi

# 4. 内存安全红线 (基于系统物理内存 12% 限制)
TOTAL_MEM_KB=$(free -k | grep Mem | awk '{print $2}')
MEM_LIMIT_BYTES=$(( TOTAL_MEM_KB * 1024 * 12 / 100 ))

if [ $MAX_BUF -gt $MEM_LIMIT_BYTES ]; then
    echo "⚠️ 内存受限：计算的缓冲区超过物理内存 12%，已自动降至安全值。"
    MAX_BUF=$MEM_LIMIT_BYTES
fi

# 5. 计算初始/默认窗口 (DEF_BUF)
# 修正发送端起步瓶颈：初始窗口不得过小
DEF_BUF=$BDP
[ $DEF_BUF -lt 262144 ] && DEF_BUF=262144  # 强制起步不低于 256KB
[ $DEF_BUF -gt $MAX_BUF ] && DEF_BUF=$MAX_BUF

echo "------------------------------------------------"
echo "匹配场景: $SCENE"
echo "输入延迟: ${RTT}ms"
echo "理论 BDP: $((BDP / 1024)) KB"
echo "最大窗口上限: $((MAX_BUF / 1024 / 1024)) MB"
echo "------------------------------------------------"

# 6. 生成并应用配置
CONF_FILE="/etc/sysctl.d/99-tcp-smart-v4.conf"

cat << EOF > $CONF_FILE
# --- 拥塞控制 ---
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# --- 缓冲区适配 ---
net.core.rmem_max = $MAX_BUF
net.core.wmem_max = $MAX_BUF
net.core.rmem_default = $DEF_BUF
net.core.wmem_default = $DEF_BUF

# TCP 接收/发送窗口：[最小, 初始默认, 最大]
net.ipv4.tcp_rmem = 4096 $DEF_BUF $MAX_BUF
net.ipv4.tcp_wmem = 4096 $DEF_BUF $MAX_BUF

# --- 实时性与丢包优化 ---
net.ipv4.tcp_notsent_lowat = $NOTSENT_LIMIT
net.ipv4.tcp_max_reordering = $REORDERING
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1

# --- 高并发加固 ---
net.core.somaxconn = 8192
net.core.netdev_max_backlog = 10000
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 25

# --- 全局内存保护 (4KB/页) ---
net.ipv4.tcp_mem = $((TOTAL_MEM_KB/3)) $((TOTAL_MEM_KB/2)) $((TOTAL_MEM_KB*3/4))
EOF

# 应用配置
sysctl --system > /dev/null

echo "✅ 调优已完成并实时生效！"
echo "💡 配置已写入: $CONF_FILE"
