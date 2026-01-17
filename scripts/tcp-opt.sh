#!/bin/bash

# ====================================================
# TCP 智能全场景调优脚本 (兼容高/低延迟)
# 核心逻辑：动态 BDP 适配 + BBR + Bufferbloat 防御
# ====================================================

if [ "$EUID" -ne 0 ]; then
    echo "❌ 请以 root 权限运行"
    exit 1
fi

# 检查并安装 bc (用于浮点运算)
if ! command -v bc &> /dev/null; then
    apt-get update && apt-get install -y bc || yum install -y bc
fi

echo "--- 正在启动网络全场景智能调优 ---"

# 1. 获取输入
read -p "请输入服务器带宽 (Mbps, 默认 100): " BW
BW=${BW:-100}
read -p "请输入预期最大往返延迟 (ms, 默认 200): " RTT
RTT=${RTT:-200}

# 2. BDP 计算
# BDP = 带宽(bps) * 延迟(s) / 8
BDP=$(echo "scale=0; ($BW * 1000000 / 8) * ($RTT / 1000)" | bc)

# 3. 缓冲区策略 (通用型)
# MAX_BUF 取 2 倍 BDP 是为了给 BBR 预留探测空间，且防止高延迟下跑不满带宽
MAX_BUF=$(echo "scale=0; $BDP * 2" | bc)

# 边界保护：最小值 4MB (现代网络基础)，最大值 64MB (防止超高延迟下的内存压力)
[ $MAX_BUF -lt 4194304 ] && MAX_BUF=4194304
[ $MAX_BUF -gt 67108864 ] && MAX_BUF=67108864

# 默认值 (Default) 取 1/2 的 BDP 或 128KB 较大者
DEF_BUF=$(echo "scale=0; $BDP / 2" | bc)
[ $DEF_BUF -lt 131072 ] && DEF_BUF=131072

# 4. 内存水位安全检查 (占物理内存 10% 左右)
TOTAL_MEM_KB=$(free -k | grep Mem | awk '{print $2}')
MEM_LIMIT=$(( TOTAL_MEM_KB * 1024 * 10 / 100 ))
[ $MAX_BUF -gt $MEM_LIMIT ] && MAX_BUF=$MEM_LIMIT

echo "------------------------------------------------"
echo "理论 BDP: $((BDP / 1024)) KB"
echo "最大窗口: $((MAX_BUF / 1024 / 1024)) MB"
echo "------------------------------------------------"

# 5. 生成配置文件
CONF_FILE="/etc/sysctl.d/99-network-universal.conf"

cat << EOF > $CONF_FILE
# --- 拥塞算法 (BBR 是通用场景的最优解) ---
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# --- 动态缓冲区设置 ---
net.core.rmem_max = $MAX_BUF
net.core.wmem_max = $MAX_BUF
# rmem: min, default, max
net.ipv4.tcp_rmem = 4096 $DEF_BUF $MAX_BUF
# wmem: min, default, max
net.ipv4.tcp_wmem = 4096 16384 $MAX_BUF

# --- 兼容低延迟的关键配置 (防止 Bufferbloat) ---
# 控制尚未发出的数据量，这是防止在低延迟网络中产生大重传的核心
net.ipv4.tcp_notsent_lowat = 131072
net.ipv4.tcp_slow_start_after_idle = 0

# --- 兼容高延迟的关键配置 (长肥管道优化) ---
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
# 开启 MTU 探测，解决长途网络 MTU 不一导致的丢包
net.ipv4.tcp_mtu_probing = 1

# --- 系统并发能力 ---
net.core.somaxconn = 8192
net.core.netdev_max_backlog = 10000
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 25

# --- 内存水位调节 ---
net.ipv4.tcp_mem = $((TOTAL_MEM_KB/3)) $((TOTAL_MEM_KB/2)) $((TOTAL_MEM_KB*3/4))
EOF

# 6. 执行生效
sysctl --system > /dev/null

echo "✅ 配置已生效！"
echo "💡 提示：此脚本通过动态 BDP 限制了最大窗口，既能让高延迟链路跑满带宽，"
echo "   又通过 notsent_lowat 机制防止了低延迟链路下的重传积压。"
