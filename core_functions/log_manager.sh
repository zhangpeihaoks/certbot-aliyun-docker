#!/bin/bash

LOG_FILE="/var/log/certbot-renew.log"

init_log() {
    [ ! -f "$LOG_FILE" ] && touch "$LOG_FILE"
    exec 3>>"$LOG_FILE"  # 创建额外的文件描述符用于日志
}

log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" >&3
}