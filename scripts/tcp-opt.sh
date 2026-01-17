#!/bin/bash

# ====================================================
# TCP 智能全场景调优脚本 (V3.1 手动精准适配版)
# 特性：带宽延迟积(BDP)动态计算、高低延迟策略切换、防缓冲区膨胀
# ====================================================

if [ "$EUID" -ne 0 ]; then
    echo "❌ 错误：请以 root 权限运行 (sudo ./script.sh)"
    exit 1
fi

echo "--- 正在启动网络环境参数匹配 ---"

# 1. 获取输入
read -p "请输入服务器带宽 (Mbps, 默认 300): " BW
BW=${BW:-300}
read -p "请输入典型往返延迟 (ms, 默认 50): " RTT
RTT=${RTT:-50}

# 2. 核心计算 (修复 Bash 整数除法先除后乘导致的 0 KB 问题)
# 逻辑：BDP (Bytes) = BW * 125 * RTT
BDP=$(( BW * RTT * 125 ))

# 3. 场景智能分类与策略选择
if [ "$RTT" -lt 50 ]; then
    # --- 低延迟场景策略 (针对 0.77% 重传率优化) ---
    SCENE="低延迟模式 (<50ms)"
    # 逻辑：减少排队，提高反馈速度
    MAX_BUF=$(( BDP * 15 / 10 ))   # 1.5倍 BDP
    NOTSENT_LIMIT=65536            # 严格限制内核积压数据 (64KB)
    REORDERING=10                  # 适度容忍乱序，减少误重传
    
    # 边界保护
    [ $MAX_BUF -lt 4194304 ] && MAX_BUF=4194304
    [ $MAX_BUF -gt 16777216 ] && MAX_BUF=16777216
else
    # --- 中高延迟场景策略 (针对 1.23% 重传率优化) ---
    SCENE="中高延迟模式 (>=50ms)"
    # 逻辑：撑大窗口，容忍乱序，填满长肥管道
    MAX_BUF=$(( BDP * 2 ))         # 2倍 BDP 确保吞吐量
    NOTSENT_LIMIT=262144           # 放宽积压限制 (256KB)
    REORDERING=20                  # 高度容忍复杂路由下的乱序
    
    # 边界保护
    [ $MAX_BUF -lt 8388608 ] && MAX_BUF=8388608
    [ $MAX_BUF -gt 67108864 ] && MAX_BUF=67108864
fi

# 4. 内存安全红线 (基于系统物理内存的 12% 限制)
TOTAL_MEM_KB=$(free -k | grep Mem | awk '{print $2}')
MEM_LIMIT_BYTES=$(( TOTAL_MEM_KB * 1024 * 12 / 100 ))
if [ $MAX_BUF -gt $MEM_LIMIT_BYTES ]; then
    echo "⚠️ 内存受限：计算的缓冲区超过 12% 物理内存，已自动降至安全值。"
    MAX_BUF=$MEM_LIMIT_BYTES
fi

# 5. 计算默认窗口
DEF_BUF=$BDP
[ $DEF_BUF -lt 131072 ] && DEF_BUF=131072
[ $DEF_BUF -gt $MAX_BUF ] && DEF_BUF=$MAX_BUF

echo "------------------------------------------------"
echo "匹配场景: $SCENE"
echo "理论 BDP: $((BDP / 1024)) KB"
echo "最大窗口上限: $((MAX_BUF / 1024 / 1024)) MB"
echo "发送队列积压限制: $((NOTSENT_LIMIT / 1024)) KB"
echo "------------------------------------------------"

# 6. 生成并应用配置
CONF_FILE="/etc/sysctl.d/99-tcp-smart-optimization.conf"
cat << EOF > $CONF_FILE
# 拥塞控制与排队算法
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# 动态缓冲区适配
net.core.rmem_max = $MAX_BUF
net.core.wmem_max = $MAX_BUF
net.ipv4.tcp_rmem = 4096 $DEF_BUF $MAX_BUF
net.ipv4.tcp_wmem = 4096 16384 $MAX_BUF

# 智能重传与延迟优化
net.ipv4.tcp_notsent_lowat = $NOTSENT_LIMIT
net.ipv4.tcp_max_reordering = $REORDERING
net.ipv4.tcp_low_latency = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1

# 高并发与稳定性加固
net.core.somaxconn = 8192
net.core.netdev_max_backlog = 10000
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 25
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1

# 系统全局内存保护
net.ipv4.tcp_mem = $((TOTAL_MEM_KB/3)) $((TOTAL_MEM_KB/2)) $((TOTAL_MEM_KB*3/4))
EOF

sysctl --system > /dev/null
echo "✅ 调优已完成并实时生效！"
