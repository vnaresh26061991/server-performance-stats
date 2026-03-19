#!/bin/bash

# =============================================================================
#  server-stats.sh — Basic Server Performance Stats
# =============================================================================

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── Helpers ───────────────────────────────────────────────────────────────────
print_header() {
    echo -e "\n${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${BOLD}${CYAN}  $1${RESET}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

# Colour-code a percentage: green < 60, yellow < 85, red >= 85
colour_pct() {
    local pct="${1%.*}"          # integer part
    if   [ "$pct" -ge 85 ]; then echo -e "${RED}${1}%${RESET}"
    elif [ "$pct" -ge 60 ]; then echo -e "${YELLOW}${1}%${RESET}"
    else                          echo -e "${GREEN}${1}%${RESET}"
    fi
}

# ── Banner ────────────────────────────────────────────────────────────────────
echo -e "${BOLD}"
echo "  ███████╗███████╗██████╗ ██╗   ██╗███████╗██████╗"
echo "  ██╔════╝██╔════╝██╔══██╗██║   ██║██╔════╝██╔══██╗"
echo "  ███████╗█████╗  ██████╔╝██║   ██║█████╗  ██████╔╝"
echo "  ╚════██║██╔══╝  ██╔══██╗╚██╗ ██╔╝██╔══╝  ██╔══██╗"
echo "  ███████║███████╗██║  ██║ ╚████╔╝ ███████╗██║  ██║"
echo "  ╚══════╝╚══════╝╚═╝  ╚═╝  ╚═══╝  ╚══════╝╚═╝  ╚═╝"
echo -e "               S T A T S${RESET}"
echo -e "${DIM}  Generated: $(date '+%Y-%m-%d %H:%M:%S %Z')${RESET}"

# ════════════════════════════════════════════════════════════════════════════
# 1. SYSTEM INFORMATION  (stretch goal)
# ════════════════════════════════════════════════════════════════════════════
print_header "⚙  System Information"

HOSTNAME=$(hostname -f 2>/dev/null || hostname)
KERNEL=$(uname -r)
ARCH=$(uname -m)

# OS pretty name — try several sources
if [ -f /etc/os-release ]; then
    OS_NAME=$(grep ^PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')
elif command -v lsb_release &>/dev/null; then
    OS_NAME=$(lsb_release -d | cut -f2-)
else
    OS_NAME="Unknown"
fi

UPTIME_STR=$(uptime -p 2>/dev/null || uptime)
LOAD_AVG=$(awk '{print $1", "$2", "$3}' /proc/loadavg)
CPU_CORES=$(nproc)

echo -e "  ${BOLD}Hostname   :${RESET} $HOSTNAME"
echo -e "  ${BOLD}OS         :${RESET} $OS_NAME"
echo -e "  ${BOLD}Kernel     :${RESET} $KERNEL  ($ARCH)"
echo -e "  ${BOLD}Uptime     :${RESET} $UPTIME_STR"
echo -e "  ${BOLD}Load Avg   :${RESET} $LOAD_AVG  (1 / 5 / 15 min)"
echo -e "  ${BOLD}CPU Cores  :${RESET} $CPU_CORES"

# ════════════════════════════════════════════════════════════════════════════
# 2. CPU USAGE
# ════════════════════════════════════════════════════════════════════════════
print_header "🖥  CPU Usage"

# Sample over 1 second with /proc/stat for accuracy; fall back to top
read_cpu() { awk '/^cpu / {print $2,$3,$4,$5,$6,$7,$8}' /proc/stat; }

CPU1=$(read_cpu); sleep 1; CPU2=$(read_cpu)

TOTAL1=$(echo $CPU1 | awk '{s=0; for(i=1;i<=NF;i++) s+=$i; print s}')
TOTAL2=$(echo $CPU2 | awk '{s=0; for(i=1;i<=NF;i++) s+=$i; print s}')
DIFF_TOTAL=$(( TOTAL2 - TOTAL1 ))

if [ "$DIFF_TOTAL" -gt 0 ] 2>/dev/null; then
    IDLE1=$(echo $CPU1 | awk '{print $4}')
    IDLE2=$(echo $CPU2 | awk '{print $4}')
    DIFF_IDLE=$(( IDLE2 - IDLE1 ))
    CPU_USED_PCT=$(awk "BEGIN {printf \"%.1f\", (1 - $DIFF_IDLE/$DIFF_TOTAL)*100}")
    CPU_IDLE_PCT=$(awk "BEGIN {printf \"%.1f\", ($DIFF_IDLE/$DIFF_TOTAL)*100}")
else
    # Fall back to top single-sample (works everywhere)
    TOP_IDLE=$(top -bn1 2>/dev/null | awk '/Cpu\(s\)|%Cpu/{
        for(i=1;i<=NF;i++) if($(i+1)~/id,?$/) {gsub(/,/,"",$i); print $i; exit}
    }')
    TOP_IDLE=${TOP_IDLE:-0}
    CPU_USED_PCT=$(awk "BEGIN {printf \"%.1f\", 100 - $TOP_IDLE}")
    CPU_IDLE_PCT=$(awk "BEGIN {printf \"%.1f\", $TOP_IDLE}")
fi

BAR_FILL=$(awk "BEGIN {printf \"%d\", $CPU_USED_PCT/5}")   # max 20 blocks
BAR_EMPTY=$(( 20 - BAR_FILL ))
BAR=$(printf '%0.s█' $(seq 1 $BAR_FILL 2>/dev/null) 2>/dev/null)
BAR+=$(printf '%0.s░' $(seq 1 $BAR_EMPTY 2>/dev/null) 2>/dev/null)

echo -e "  Used : $(colour_pct $CPU_USED_PCT)   Idle : ${GREEN}${CPU_IDLE_PCT}%${RESET}"
echo -e "  [${YELLOW}${BAR}${RESET}] ${CPU_USED_PCT}%"

# Per-core breakdown (optional, via /proc/stat)
echo -e "\n  ${DIM}Per-core snapshot (via top):${RESET}"
top -bn1 | awk '/^%Cpu/{
    for(i=1;i<=NF;i++) if($i~/^[0-9]/ && $(i+1)~/id/) idle=$(i); 
}' 2>/dev/null
# Simpler: just show mpstat if available
if command -v mpstat &>/dev/null; then
    mpstat -P ALL 1 1 | awk 'NR>3 && /^[0-9]|^Average/ && $2~/^[0-9]+$/ {
        used=100-$NF
        printf "  Core %-3s: %.1f%% used\n", $2, used
    }'
fi

# ════════════════════════════════════════════════════════════════════════════
# 3. MEMORY USAGE
# ════════════════════════════════════════════════════════════════════════════
print_header "🧠  Memory Usage"

MEM_TOTAL=$(awk '/^MemTotal/{print $2}' /proc/meminfo)
MEM_FREE=$(awk '/^MemFree/{print $2}' /proc/meminfo)
MEM_AVAIL=$(awk '/^MemAvailable/{print $2}' /proc/meminfo)
MEM_BUFFERS=$(awk '/^Buffers/{print $2}' /proc/meminfo)
MEM_CACHED=$(awk '/^Cached/{print $2}' /proc/meminfo)
MEM_USED=$(( MEM_TOTAL - MEM_AVAIL ))
MEM_USED_PCT=$(awk "BEGIN {printf \"%.1f\", ($MEM_USED/$MEM_TOTAL)*100}")
MEM_FREE_PCT=$(awk "BEGIN {printf \"%.1f\", ($MEM_AVAIL/$MEM_TOTAL)*100}")

to_mb() { awk "BEGIN {printf \"%.1f\", $1/1024}"; }
to_gb() { awk "BEGIN {printf \"%.2f\", $1/1024/1024}"; }

echo -e "  ${BOLD}Total     :${RESET} $(to_mb $MEM_TOTAL) MB  ($(to_gb $MEM_TOTAL) GB)"
echo -e "  ${BOLD}Used      :${RESET} $(to_mb $MEM_USED) MB  — $(colour_pct $MEM_USED_PCT)"
echo -e "  ${BOLD}Available :${RESET} $(to_mb $MEM_AVAIL) MB  — ${GREEN}${MEM_FREE_PCT}%${RESET} free"
echo -e "  ${BOLD}Buffers   :${RESET} $(to_mb $MEM_BUFFERS) MB"
echo -e "  ${BOLD}Cached    :${RESET} $(to_mb $MEM_CACHED) MB"

MEM_BAR_FILL=$(awk "BEGIN {printf \"%d\", $MEM_USED_PCT/5}")
MEM_BAR_EMPTY=$(( 20 - MEM_BAR_FILL ))
MEM_BAR=$(printf '%0.s█' $(seq 1 $MEM_BAR_FILL  2>/dev/null) 2>/dev/null)
MEM_BAR+=$(printf '%0.s░' $(seq 1 $MEM_BAR_EMPTY 2>/dev/null) 2>/dev/null)
echo -e "\n  [${YELLOW}${MEM_BAR}${RESET}] ${MEM_USED_PCT}% used"

# Swap
SWAP_TOTAL=$(awk '/^SwapTotal/{print $2}' /proc/meminfo)
SWAP_FREE=$(awk '/^SwapFree/{print $2}' /proc/meminfo)
SWAP_USED=$(( SWAP_TOTAL - SWAP_FREE ))
if [ "$SWAP_TOTAL" -gt 0 ]; then
    SWAP_PCT=$(awk "BEGIN {printf \"%.1f\", ($SWAP_USED/$SWAP_TOTAL)*100}")
    echo -e "\n  ${BOLD}Swap Total:${RESET} $(to_mb $SWAP_TOTAL) MB"
    echo -e "  ${BOLD}Swap Used :${RESET} $(to_mb $SWAP_USED) MB  — $(colour_pct $SWAP_PCT)"
else
    echo -e "\n  ${DIM}Swap: not configured${RESET}"
fi

# ════════════════════════════════════════════════════════════════════════════
# 4. DISK USAGE
# ════════════════════════════════════════════════════════════════════════════
print_header "💾  Disk Usage"

echo -e "  ${BOLD}$(printf '%-20s %8s %8s %8s %6s' 'Filesystem' 'Total' 'Used' 'Free' 'Use%')${RESET}"
echo -e "  ${DIM}$(printf '%-20s %8s %8s %8s %6s' '──────────────────' '──────' '──────' '──────' '────')${RESET}"

df -h --output=source,size,used,avail,pcent,target 2>/dev/null | \
grep -E '^(/dev|tmpfs|overlay)' | sort -k6 | \
while read -r src size used avail pcent target; do
    pct_num="${pcent%\%}"
    colored_pct=$(colour_pct "$pct_num")
    printf "  %-20s %8s %8s %8s " "$src" "$size" "$used" "$avail"
    echo -e "${colored_pct}  ${DIM}${target}${RESET}"
done

# ════════════════════════════════════════════════════════════════════════════
# 5. TOP 5 PROCESSES BY CPU
# ════════════════════════════════════════════════════════════════════════════
print_header "📊  Top 5 Processes by CPU Usage"

echo -e "  ${BOLD}$(printf '%-8s %-10s %6s %6s  %s' 'PID' 'USER' 'CPU%' 'MEM%' 'COMMAND')${RESET}"
echo -e "  ${DIM}$(printf '%-8s %-10s %6s %6s  %s' '───────' '─────────' '─────' '─────' '───────────────────')${RESET}"

ps aux --sort=-%cpu 2>/dev/null | awk 'NR>=2 && NR<=7 {
    printf "  %-8s %-10s %6s %6s  %s\n", $2, $1, $3, $4, $11
}'

# ════════════════════════════════════════════════════════════════════════════
# 6. TOP 5 PROCESSES BY MEMORY
# ════════════════════════════════════════════════════════════════════════════
print_header "📊  Top 5 Processes by Memory Usage"

echo -e "  ${BOLD}$(printf '%-8s %-10s %6s %6s  %s' 'PID' 'USER' 'MEM%' 'CPU%' 'COMMAND')${RESET}"
echo -e "  ${DIM}$(printf '%-8s %-10s %6s %6s  %s' '───────' '─────────' '─────' '─────' '───────────────────')${RESET}"

ps aux --sort=-%mem 2>/dev/null | awk 'NR>=2 && NR<=7 {
    printf "  %-8s %-10s %6s %6s  %s\n", $2, $1, $4, $3, $11
}'

# ════════════════════════════════════════════════════════════════════════════
# 7. LOGGED-IN USERS  (stretch goal)
# ════════════════════════════════════════════════════════════════════════════
print_header "👥  Logged-in Users"

who_out=$(who 2>/dev/null)
if [ -z "$who_out" ]; then
    echo -e "  ${DIM}No users currently logged in.${RESET}"
else
    echo -e "  ${BOLD}$(printf '%-12s %-10s %-20s %s' 'USER' 'TTY' 'LOGIN TIME' 'FROM')${RESET}"
    echo "$who_out" | awk '{
        from = (NF>=5) ? $NF : "local"
        printf "  %-12s %-10s %-20s %s\n", $1, $2, $3" "$4, from
    }'
fi
echo -e "  ${DIM}Total sessions: $(who 2>/dev/null | wc -l)${RESET}"

# ════════════════════════════════════════════════════════════════════════════
# 8. FAILED LOGIN ATTEMPTS  (stretch goal)
# ════════════════════════════════════════════════════════════════════════════
print_header "🔐  Failed Login Attempts (last 24 h)"

FAILED=0
if command -v journalctl &>/dev/null; then
    FAILED=$(journalctl _SYSTEMD_UNIT=sshd.service --since "24 hours ago" 2>/dev/null \
             | grep -c "Failed password" || true)
elif [ -f /var/log/auth.log ]; then
    FAILED=$(grep "Failed password" /var/log/auth.log 2>/dev/null | \
             awk -v d="$(date --date='24 hours ago' '+%b %e')" '$0 >= d' | wc -l)
elif [ -f /var/log/secure ]; then
    FAILED=$(grep "Failed password" /var/log/secure 2>/dev/null | wc -l)
fi

if [ "$FAILED" -gt 50 ]; then
    echo -e "  Failed SSH logins : ${RED}${BOLD}${FAILED}${RESET} ⚠️  (high — investigate!)"
elif [ "$FAILED" -gt 10 ]; then
    echo -e "  Failed SSH logins : ${YELLOW}${FAILED}${RESET}"
else
    echo -e "  Failed SSH logins : ${GREEN}${FAILED}${RESET}"
fi

# Top offending IPs (if available)
if command -v journalctl &>/dev/null; then
    TOP_IPS=$(journalctl _SYSTEMD_UNIT=sshd.service --since "24 hours ago" 2>/dev/null \
              | grep "Failed password" \
              | grep -oP 'from \K[\d.]+' \
              | sort | uniq -c | sort -rn | head -5)
    if [ -n "$TOP_IPS" ]; then
        echo -e "\n  ${BOLD}Top offending IPs:${RESET}"
        echo "$TOP_IPS" | awk '{printf "  %5s attempts — %s\n", $1, $2}'
    fi
fi

# ════════════════════════════════════════════════════════════════════════════
# 9. NETWORK STATS  (stretch goal)
# ════════════════════════════════════════════════════════════════════════════
print_header "🌐  Network Interfaces"

if command -v ip &>/dev/null; then
    ip -brief addr show 2>/dev/null | awk '{
        printf "  %-12s %-12s %s\n", $1, $2, $3
    }'
else
    ifconfig 2>/dev/null | awk '/^[a-z]/{iface=$1} /inet /{print "  "iface"  "$2}'
fi

# ════════════════════════════════════════════════════════════════════════════
# Footer
# ════════════════════════════════════════════════════════════════════════════
echo -e "\n${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${DIM}  server-stats.sh — run complete at $(date '+%H:%M:%S')${RESET}"
echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
