#!/bin/bash

LOG_FILE="/var/log/certbot-renew.log"

# 判断日志文件是否存在，不存在则创建
if [ ! -f "$LOG_FILE" ]; then
    touch "$LOG_FILE"
fi

CERT_PATH="$RENEWED_LINEAGE/fullchain.pem"
KEY_PATH="$RENEWED_LINEAGE/privkey.pem"

if [ -f "$CERT_PATH" ] && [ -f "$KEY_PATH" ]; then
    CERT_CONTENT=$(cat "$CERT_PATH")
    KEY_CONTENT=$(cat "$KEY_PATH")

    # 判断是否有 webhook 地址
    if [ -z "$WEBHOOK_URL" ]; then
        echo "未设置 WEBHOOK_URL 环境变量，无法发送证书内容到 webhook。" >> "$LOG_FILE"
        exit 1
    fi
    
    # 飞书消息头
    FEISHU_HEADER='{
        "msg_type": "post",
        "content": {
            "post": {
                "zh_cn": {
                    "title": "证书更新通知",
                    "content": [
                        [
                            {
                                "tag": "text",
                                "text": "域名：'
    FEISHU_FOOTER='"\n                            }
                        ]
                    ]
                }
            }
        }
    }'

    # 构建消息内容
    DOMAIN_NAME=$(openssl x509 -in "$CERT_PATH" -noout -subject | sed 's/.*CN=//;s/,.*//')
    if [ -z "$DOMAIN_NAME" ]; then
        DOMAIN_NAME="未知域名"
    fi

    if [ -n "$ENCRYPT_KEY" ]; then
        echo "对证书内容进行加密..." >> "$LOG_FILE"
        IV=$(openssl rand -hex 16)  # 生成16字节随机IV

        # 加密证书内容
        ENCRYPTED_CERT_CONTENT=$(echo "$CERT_CONTENT" | openssl enc -aes-256-cbc -K "$ENCRYPT_KEY" -iv "$IV" -base64 -A 2>/dev/null)
        if [ -z "$ENCRYPTED_CERT_CONTENT" ]; then
            echo "证书内容加密失败" >> "$LOG_FILE"
            exit 1
        fi

        # 加密密钥内容
        ENCRYPTED_KEY_CONTENT=$(echo "$KEY_CONTENT" | openssl enc -aes-256-cbc -K "$ENCRYPT_KEY" -iv "$IV" -base64 -A 2>/dev/null)
        if [ -z "$ENCRYPTED_KEY_CONTENT" ]; then
            echo "密钥内容加密失败" >> "$LOG_FILE"
            exit 1
        fi

        # 构建飞书加密消息
        FEISHU_BODY="${FEISHU_HEADER}${DOMAIN_NAME}"
        FEISHU_BODY+=',\n                                "text": "证书已加密，请使用以下信息解密：\nIV: '
        FEISHU_BODY+="${IV}"
        FEISHU_BODY+='\n加密证书：\n'
        FEISHU_BODY+="${ENCRYPTED_CERT_CONTENT}"
        FEISHU_BODY+='\n\n加密密钥：\n'
        FEISHU_BODY+="${ENCRYPTED_KEY_CONTENT}"
        FEISHU_BODY+="${FEISHU_FOOTER}"

        echo "发送加密的证书内容到飞书..." >> "$LOG_FILE"
    else
        # 构建飞书明文消息
        FEISHU_BODY="${FEISHU_HEADER}${DOMAIN_NAME}"
        FEISHU_BODY+=',\n                                "text": "证书内容：\n'
        FEISHU_BODY+="${CERT_CONTENT}"
        FEISHU_BODY+='\n\n私钥内容：\n'
        FEISHU_BODY+="${KEY_CONTENT}"
        FEISHU_BODY+="${FEISHU_FOOTER}"

        echo "发送未加密的证书内容到飞书..." >> "$LOG_FILE"
    fi

    # 发送到飞书Webhook
    RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
        -d "$FEISHU_BODY" \
        "$WEBHOOK_URL" 2>> "$LOG_FILE")

    # 检查飞书响应
    if ! echo "$RESPONSE" | grep -q '"StatusCode":0'; then
        echo "飞书消息发送失败: $RESPONSE" >> "$LOG_FILE"
        exit 1
    fi

else
    echo "未找到证书文件，无法发送到飞书。" >> "$LOG_FILE"
fi
