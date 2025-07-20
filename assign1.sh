----- assign 1 ----
#!/bin/bash

# Check for log file argument
if [ -z "$1" ]; then
    echo "Usage: $0 /home/student/projects/assignments/assign1.sh"
    exit 1
fi

LOG_FILE="$1"

if [ ! -f "$LOG_FILE" ]; then
    echo "Error: File '$LOG_FILE' not found!"
    exit 2
fi

# Variables
NOW=$(date "+%Y%m%d_%H%M%S")
HUMAN_DATE=$(date)
REPORT_FILE="log_analysis_$NOW.txt"
FILE_SIZE_BYTES=$(stat -c%s "$LOG_FILE")
FILE_SIZE_MB=$(awk "BEGIN {printf \"%.1f\", $FILE_SIZE_BYTES/1024/1024}")

# Count message types
ERROR_COUNT=$(grep -c "ERROR" "$LOG_FILE")
WARNING_COUNT=$(grep -c "WARNING" "$LOG_FILE")
INFO_COUNT=$(grep -c "INFO" "$LOG_FILE")

# Top 5 error messages
TOP_ERRORS=$(grep "ERROR" "$LOG_FILE" | \
             sed -E 's/^.*ERROR[: ]+//' | \
             sort | uniq -c | sort -nr | head -n 5)

# First and last error
FIRST_ERROR=$(grep "ERROR" "$LOG_FILE" | head -n 1)
LAST_ERROR=$(grep "ERROR" "$LOG_FILE" | tail -n 1)

# Error frequency by hour
declare -A hour_bins
for h in 00 04 08 12 16 20; do hour_bins[$h]=0; done

grep "ERROR" "$LOG_FILE" | while read -r line; do
    ts=$(echo "$line" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}')
    hour=${ts:11:2}
    if [ "$hour" -ge 0 ] && [ "$hour" -lt 4 ]; then
        ((hour_bins["00"]++))
    elif [ "$hour" -ge 4 ] && [ "$hour" -lt 8 ]; then
        ((hour_bins["04"]++))
    elif [ "$hour" -ge 8 ] && [ "$hour" -lt 12 ]; then
        ((hour_bins["08"]++))
    elif [ "$hour" -ge 12 ] && [ "$hour" -lt 16 ]; then
        ((hour_bins["12"]++))
    elif [ "$hour" -ge 16 ] && [ "$hour" -lt 20 ]; then
        ((hour_bins["16"]++))
    elif [ "$hour" -ge 20 ]; then
        ((hour_bins["20"]++))
    fi
done

# Draw frequency bars
draw_bar() {
    count=$1
    bar=""
    for ((i = 0; i < count / 10; i++)); do
        bar+="█"
    done
    echo "$bar"
}

# Write Report
{
echo "===== LOG FILE ANALYSIS REPORT ====="
echo "File: $LOG_FILE"
echo "Analyzed on: $HUMAN_DATE"
echo "Size: ${FILE_SIZE_MB}MB ($FILE_SIZE_BYTES bytes)"
echo ""
echo "MESSAGE COUNTS:"
printf "ERROR: %'d messages\n" "$ERROR_COUNT"
printf "WARNING: %'d messages\n" "$WARNING_COUNT"
printf "INFO: %'d messages\n" "$INFO_COUNT"
echo ""
echo "TOP 5 ERROR MESSAGES:"
echo "$TOP_ERRORS" | while read -r count msg; do
    printf " %3d - %s\n" "$count" "$msg"
done
echo ""
echo "ERROR TIMELINE:"
echo "First error: $FIRST_ERROR"
echo "Last error:  $LAST_ERROR"
echo ""
echo "Error frequency by hour:"
for h in 00 04 08 12 16 20; do
    bar=$(draw_bar "${hour_bins[$h]}")
    printf "%s-%02d: %s (%d)\n" "$h" $((10#$h + 4)) "$bar" "${hour_bins[$h]}"
done
echo ""
echo "Report saved to: $REPORT_FILE"
} | tee "$REPORT_FILE"