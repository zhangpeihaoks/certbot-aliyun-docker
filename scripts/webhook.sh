#!/bin/bash

# webhook.sh - 极简版实现
LOG_FILE="/var/log/certbot-renew.log"

[ ! -f "$LOG_FILE" ] && touch "$LOG_FILE"

CERT_PATH="$RENEWED_LINEAGE/fullchain.pem"
KEY_PATH="$RENEWED_LINEAGE/privkey.pem"

if [ -f "$CERT_PATH" ] && [ -f "$KEY_PATH" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') 找到证书文件，准备发送通知" >> "$LOG_FILE"

    # 获取证书有效期信息
    END_DATE=$(openssl x509 -enddate -noout -in "$CERT_PATH" | cut -d= -f2)

    # 获取证书序列号
    SERIAL=$(openssl x509 -serial -noout -in "$CERT_PATH" | cut -d= -f2)

    # 获取颁发者
    ISSUER=$(openssl x509 -issuer -noout -in "$CERT_PATH" | sed 's/issuer= //')

    # 构建更详细的消息
    MESSAGE="证书更新成功
    域名: $DOMAIN
    有效期: $END_DATE
    序列号: $SERIAL
    颁发者: $ISSUER
    路径: $CERT_PATH"

    # 飞书Webhook请求（极简版）
    curl -s -X POST -H "Content-Type: application/json" \
        -d "{\"msg_type\": \"text\", \"content\": {\"text\": \"$MESSAGE\"}}" \
        "$WEBHOOK_URL" >> "$LOG_FILE" 2>&1

    echo "$(date '+%Y-%m-%d %H:%M:%S') 飞书通知已发送" >> "$LOG_FILE"
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') 错误：未找到证书文件" >> "$LOG_FILE"
fi