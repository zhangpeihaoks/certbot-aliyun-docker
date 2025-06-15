#!/bin/bash

LOG_FILE="/var/log/certbot-renew.log"

[ ! -f "$LOG_FILE" ] && touch "$LOG_FILE"

CERT_PATH="$RENEWED_LINEAGE/fullchain.pem"
KEY_PATH="$RENEWED_LINEAGE/privkey.pem"

if [ -f "$CERT_PATH" ] && [ -f "$KEY_PATH" ]; then
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$TIMESTAMP 找到证书文件，准备发送通知" >> "$LOG_FILE"

    # 获取证书信息
    END_DATE=$(openssl x509 -enddate -noout -in "$CERT_PATH" | cut -d= -f2)

    # 构建飞书消息的JSON
    JSON_PAYLOAD=$(cat <<EOF
{
    "msg_type": "post",
    "content": {
        "post": {
            "zh_cn": {
                "title": "SSL证书更新通知",
                "content": [
                    [
                        {
                            "tag": "text",
                            "text": "域名: $DOMAIN"
                        }
                    ],
                    [
                        {
                            "tag": "text",
                            "text": "有效期至: $END_DATE"
                        }
                    ],
                    [
                        {
                            "tag": "a",
                            "text": "查看证书详情",
                            "href": "https://crt.sh/?q=$DOMAIN"
                        }
                    ]
                ]
            }
        }
    }
}
EOF
)

    # 发送飞书通知
    curl -s -X POST -H "Content-Type: application/json" \
        -d "$JSON_PAYLOAD" \
        "$WEBHOOK_URL" >> "$LOG_FILE" 2>&1

    echo "$TIMESTAMP 飞书通知已发送" >> "$LOG_FILE"
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') 错误：未找到证书文件" >> "$LOG_FILE"
fi