#!/bin/bash
LOG=~/monitor.log
echo "=== Monitor Start: $(date) ===" | tee -a $LOG

while true; do
    PID=$(pgrep -f agent-leak-app | head -1)
    if [ -z "$PID" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] PROCESS NOT FOUND" | tee -a $LOG
    else
        STAT=$(ps -p $PID -o %cpu,%mem,rss,vsz --no-headers 2>/dev/null)
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] PID:$PID CPU:%cpu MEM:%mem RSS/VSZ: $STAT" | tee -a $LOG
    fi
    sleep 3
done