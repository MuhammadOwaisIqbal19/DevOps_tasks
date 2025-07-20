
#!/bin/bash
# Config
refresh_rate=3
filter="All"
log_file="health_alerts.log"
declare -A usage_thresholds=([CPU]=80 [MEMORY]=75 [DISK]=75)

# Colors
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m" # No Color

# Cleanup on exit
trap "tput cnorm; clear; exit" SIGINT SIGTERM

draw_bar() {
    local usage=$1
    local length=40
    local filled=$((usage * length / 100))
    local empty=$((length - filled))
    local bar=$(printf "%0.s█" $(seq 1 $filled))
    bar+=$(printf "%0.s░" $(seq 1 $empty))

    # Color code
    if (( usage >= 90 )); then
        echo -e "${RED}${bar}${NC}"
    elif (( usage >= 75 )); then
        echo -e "${YELLOW}${bar}${NC}"
    else
        echo -e "${GREEN}${bar}${NC}"
    fi
}

log_alert() {
    echo "[$(date +%T)] $1" >> "$log_file"
}

while true; do
    clear
    tput civis
    now=$(date "+%Y-%m-%d")
    time_now=$(date "+%T")
    host=$(hostname)
    uptime_str=$(uptime -p | sed 's/up //')
    load_avg=$(cut -d " " -f1-3 /proc/loadavg)

    # CPU
    cpu_idle=$(top -bn1 | grep "Cpu(s)" | awk '{print $8}')
    cpu_usage=$(printf "%.0f" "$(echo "100 - $cpu_idle" | bc)")
    cpu_bar=$(draw_bar "$cpu_usage")
    cpu_top=$(ps -eo comm,%cpu --sort=-%cpu | head -n 4 | tail -n 3)

    # Memory
    mem_stats=$(free -m)
    mem_total=$(echo "$mem_stats" | awk '/Mem:/ {print $2}')
    mem_used=$(echo "$mem_stats" | awk '/Mem:/ {print $3}')
    mem_percent=$(( 100 * mem_used / mem_total ))
    mem_bar=$(draw_bar "$mem_percent")
    mem_free=$(echo "$mem_stats" | awk '/Mem:/ {print $4}')
    mem_cache=$(echo "$mem_stats" | awk '/Mem:/ {print $6}')
    mem_buffers=$(echo "$mem_stats" | awk '/Mem:/ {print $7}')

    # Disk
    disk_info=$(df -h --output=target,pcent | grep -v "Use")
    disk_lines=""
    while read -r line; do
        mount=$(echo "$line" | awk '{print $1}')
        percent=$(echo "$line" | awk '{print $2}' | tr -d '%')
        bar=$(draw_bar "$percent")
        status="[OK]"
        (( percent > usage_thresholds[DISK] )) && status="[WARNING]" && log_alert "Disk usage on $mount exceeded ${usage_thresholds[DISK]}% ($percent%)"
        disk_lines+="$mount : ${percent}% $bar $status\n"
    done <<< "$disk_info"

    # Network
    rx_before=$(cat /sys/class/net/eth0/statistics/rx_bytes)
    tx_before=$(cat /sys/class/net/eth0/statistics/tx_bytes)
    sleep 1
    rx_after=$(cat /sys/class/net/eth0/statistics/rx_bytes)
    tx_after=$(cat /sys/class/net/eth0/statistics/tx_bytes)

    rx_rate=$(echo "scale=1; ($rx_after - $rx_before)/1024/1024" | bc)
    tx_rate=$(echo "scale=1; ($tx_after - $tx_before)/1024/1024" | bc)
    rx_bar=$(draw_bar "$(printf "%.0f" "$(echo "$rx_rate*10" | bc)")")
    tx_bar=$(draw_bar "$(printf "%.0f" "$(echo "$tx_rate*10" | bc)")")

    # Logging alerts
    if (( cpu_usage > usage_thresholds[CPU] )); then
        log_alert "CPU usage exceeded ${usage_thresholds[CPU]}% (${cpu_usage}%)"
    fi
    if (( mem_percent > usage_thresholds[MEMORY] )); then
        log_alert "Memory usage exceeded ${usage_thresholds[MEMORY]}% (${mem_percent}%)"
    fi

    # Header
    echo -e "╔════════════ SYSTEM HEALTH MONITOR v1.0 ════════════╗  [R]efresh rate: ${refresh_rate}s"
    printf "║ Hostname: %-25s  Date: %-10s ║  [F]ilter: %s\n" "$host" "$now" "$filter"
    printf "║ Uptime: %-43s ║  [Q]uit\n" "$uptime_str"
    echo -e "╚═══════════════════════════════════════════════════════════════════════╝"

    [[ "$filter" == "All" || "$filter" == "CPU" ]] && {
        echo -e "\nCPU USAGE: $cpu_usage% $cpu_bar [$( ((cpu_usage>=90)) && echo CRITICAL || ((cpu_usage>=75)) && echo WARNING || echo OK )]"
        echo -e "  Top Processes:\n  $cpu_top"
    }

    [[ "$filter" == "All" || "$filter" == "MEMORY" ]] && {
        echo -e "\nMEMORY: ${mem_used}MB/${mem_total}MB (${mem_percent}%) $mem_bar [$( ((mem_percent>=90)) && echo CRITICAL || ((mem_percent>=75)) && echo WARNING || echo OK )]"
        echo -e "  Free: ${mem_free}MB | Cache: ${mem_cache}MB | Buffers: ${mem_buffers}MB"
    }

    [[ "$filter" == "All" ]] && {
        echo -e "\nDISK USAGE:"
        echo -e "$disk_lines"

        echo -e "NETWORK:"
        echo -e "  eth0 (in) : ${rx_rate} MB/s $rx_bar [OK]"
        echo -e "  eth0 (out): ${tx_rate} MB/s $tx_bar [OK]"

        echo -e "\nLOAD AVERAGE: $load_avg"
    }

    echo -e "\nRECENT ALERTS:"
    tail -n 5 "$log_file" 2>/dev/null || echo "No alerts yet."

    # Read input with timeout
    read -t "$refresh_rate" -n 1 -s key
    if [[ "$key" == "q" || "$key" == "Q" ]]; then
        tput cnorm
        clear
        echo "Exiting monitor..."
        exit
    elif [[ "$key" == "r" || "$key" == "R" ]]; then
        read -p "Enter new refresh rate (seconds): " new_rate
        [[ "$new_rate" =~ ^[1-9][0-9]*$ ]] && refresh_rate="$new_rate"
    elif [[ "$key" == "f" || "$key" == "F" ]]; then
        echo -e "\nSelect filter: (1) All  (2) CPU  (3) MEMORY"
        read -n 1 fkey
        case "$fkey" in
            1) filter="All" ;;
            2) filter="CPU" ;;
            3) filter="MEMORY" ;;
        esac
    fi
done