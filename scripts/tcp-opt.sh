#!/bin/bash

# ====================================================
# TCP 智能全场景调优脚本 (V2.2 逻辑修复版)
# 修复了在 Bash 中 BDP 计算可能出现的归零或溢出问题
# ====================================================

if [ "$EUID" -ne 0 ]; then
    echo "❌ 错误：请以 root 权限运行"
    exit 1
fi

echo "--- 正在启动网络深度调优 (已修正计算逻辑) ---"

# 获取输入
read -p "请输入服务器带宽 (Mbps, 默认 300): " BW
BW=${BW:-300}
read -p "请输入预期最大往返延迟 (ms, 默认 290): " RTT
RTT=${RTT:-290}

# --- 核心修复：BDP 计算逻辑 ---
# 逻辑：BDP = (BW * 1000000 / 8) * (RTT / 1000)
# 为了防止 Bash 整数除法先算 RTT/1000 = 0，我们将乘法全部提前
# BDP = BW * RTT * 1000000 / 8000 = BW * RTT * 125
BDP=$(( BW * RTT * 125 ))

# 缓冲区策略
MAX_BUF=$(( BDP * 2 ))

# 边界保护
[ $MAX_BUF -lt 4194304 ] && MAX_BUF=4194304
[ $MAX_BUF -gt 67108864 ] && MAX_BUF=67108864

DEF_BUF=$BDP
[ $DEF_BUF -lt 131072 ] && DEF_BUF=131072
[ $DEF_BUF -gt $MAX_BUF ] && DEF_BUF=$MAX_BUF

# 内存安全检查 (物理内存 12% 限制)
TOTAL_MEM_KB=$(free -k | grep Mem | awk '{print $2}')
MEM_LIMIT_BYTES=$(( TOTAL_MEM_KB * 1024 * 12 / 100 ))
if [ $MAX_BUF -gt $MEM_LIMIT_BYTES ]; then
    MAX_BUF=$MEM_LIMIT_BYTES
fi

echo "------------------------------------------------"
echo "计算结果 (验证):"
echo "理论 BDP: $((BDP / 1024)) KB"
echo "最大窗口限制: $((MAX_BUF / 1024 / 1024)) MB"
echo "------------------------------------------------"

# 写入配置
CONF_FILE="/etc/sysctl.d/99-network-universal.conf"
cat << EOF > $CONF_FILE
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = $MAX_BUF
net.core.wmem_max = $MAX_BUF
net.ipv4.tcp_rmem = 4096 $DEF_BUF $MAX_BUF
net.ipv4.tcp_wmem = 4096 16384 $MAX_BUF
net.ipv4.tcp_notsent_lowat = 131072
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_low_latency = 1
net.ipv4.tcp_mtu_probing = 1
net.core.somaxconn = 8192
net.core.netdev_max_backlog = 10000
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 25
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_mem = $((TOTAL_MEM_KB/3)) $((TOTAL_MEM_KB/2)) $((TOTAL_MEM_KB*3/4))
EOF

sysctl --system > /dev/null
echo "✅ 配置已生效！"
