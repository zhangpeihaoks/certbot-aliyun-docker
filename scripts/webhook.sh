#!/bin/bash

LOG_FILE="/var/log/certbot-renew.log"

[ ! -f "$LOG_FILE" ] && touch "$LOG_FILE"

CERT_PATH="$RENEWED_LINEAGE/fullchain.pem"
KEY_PATH="$RENEWED_LINEAGE/privkey.pem"

# 获取证书信息函数
get_cert_info() {
    local cert_path="$1"
    local domain="$2"

    END_DATE=$(openssl x509 -enddate -noout -in "$cert_path" | cut -d= -f2)
    SERIAL=$(openssl x509 -serial -noout -in "$cert_path" | cut -d= -f2)
    ISSUER=$(openssl x509 -issuer -noout -in "$cert_path" | sed 's/issuer= //')

    # 计算剩余天数
    end_epoch=$(date -d "$END_DATE" +%s)
    now_epoch=$(date +%s)
    DAYS_LEFT=$(( (end_epoch - now_epoch) / 86400 ))

    # 根据剩余天数设置状态
    if [ $DAYS_LEFT -lt 7 ]; then
        STATUS="⚠️ 即将过期 ($DAYS_LEFT 天后)"
    elif [ $DAYS_LEFT -lt 30 ]; then
        STATUS="🟡 即将到期 ($DAYS_LEFT 天后)"
    else
        STATUS="✅ 有效 ($DAYS_LEFT 天后)"
    fi

    # 构建消息
    MESSAGE="SSL证书状态: $STATUS\n域名: $domain\n有效期至: $END_DATE\n序列号: $SERIAL\n颁发机构: $ISSUER"

    echo "$MESSAGE"
}

# 发送通知函数
send_notification() {
    local message="$1"
    local event_type="$2"

    # 构建飞书消息
    JSON_PAYLOAD='{
        "msg_type": "text",
        "content": {
            "text": "'"$message"'"
        }
    }'

    # 发送通知
    curl -s -X POST -H "Content-Type: application/json" \
        -d "$JSON_PAYLOAD" \
        "$WEBHOOK_URL" >> "$LOG_FILE" 2>&1

    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$TIMESTAMP [$event_type] 飞书通知已发送" >> "$LOG_FILE"
}

# 主逻辑
if [ -f "$CERT_PATH" ] && [ -f "$KEY_PATH" ]; then
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$TIMESTAMP 找到证书文件，准备发送通知" >> "$LOG_FILE"

    # 获取证书信息
    MESSAGE=$(get_cert_info "$CERT_PATH" "$DOMAIN")

    # 确定事件类型
    if [ -n "$RENEWED_LINEAGE" ]; then
        EVENT_TYPE="证书更新"
        MESSAGE="🎉 证书已成功更新！\n$MESSAGE"
    else
        EVENT_TYPE="证书检查"
        MESSAGE="ℹ️ 证书状态检查\n$MESSAGE"
    fi

    # 发送通知
    send_notification "$MESSAGE" "$EVENT_TYPE"

else
    echo "$(date '+%Y-%m-%d %H:%M:%S') 错误：未找到证书文件" >> "$LOG_FILE"

    # 发送错误通知
    MESSAGE="❌ 错误：未找到证书文件\n域名: $DOMAIN\n请检查证书申请流程"
    send_notification "$MESSAGE" "证书错误"
fi