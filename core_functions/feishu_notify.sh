#!/bin/bash

send_to_feishu() {
    local domain="$1"
    local cert_content="$2"
    local key_content="$3"
    local encrypt_key="${4:-}"

    # 修复 MD5 命令问题
    if ! command -v md5 &> /dev/null; then
        # Alpine Linux 使用 md5sum
        md5() {
            md5sum | cut -d' ' -f1
        }
    fi

    # 基础JSON结构
    local json_template='{
        "msg_type": "post",
        "content": {
            "post": {
                "zh_cn": {
                    "title": "证书更新通知",
                    "content": [
                        [
                            {
                                "tag": "text",
                                "text": "DOMAIN_CONTENT"
                            }
                        ]
                    ]
                }
            }
        }
    }'

    # 处理加密逻辑
    local message_content
    if [ -n "$encrypt_key" ]; then
        log "对证书内容进行加密..."

        # 生成安全的密钥（SHA256哈希）
        local secure_key=$(echo -n "$encrypt_key" | sha256sum | cut -d' ' -f1)
        local iv=$(openssl rand -hex 16)

        # 加密证书和私钥
        local encrypted_cert=$(echo "$cert_content" | openssl enc -aes-256-cbc -K "$secure_key" -iv "$iv" -base64 -A)
        local encrypted_key=$(echo "$key_content" | openssl enc -aes-256-cbc -K "$secure_key" -iv "$iv" -base64 -A)

        message_content="域名：$domain\n证书已加密，请使用以下信息解密：\nIV: $iv\n加密证书：\n$encrypted_cert\n\n加密密钥：\n$encrypted_key"
    else
        message_content="域名：$domain\n证书内容：\n$cert_content\n\n私钥内容：\n$key_content"
    fi

    # 安全插入内容
    local json_payload=$(echo "$json_template" | sed "s|DOMAIN_CONTENT|$message_content|")

    # 发送请求
    local response=$(curl -s -X POST -H "Content-Type: application/json" \
        -d "$json_payload" \
        "$WEBHOOK_URL" 2>&1)

    # 检查响应
    if ! echo "$response" | grep -q '"StatusCode":0'; then
        log "飞书消息发送失败: $response"
        return 1
    fi

    log "飞书通知发送成功"
    return 0
}