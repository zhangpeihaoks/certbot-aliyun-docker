#!/bin/bash

# 加载核心功能
source /usr/local/core_functions/log_manager.sh
source /usr/local/core_functions/feishu_notify.sh

init_log
log "执行 Webhook 部署"

CERT_PATH="$RENEWED_LINEAGE/fullchain.pem"
KEY_PATH="$RENEWED_LINEAGE/privkey.pem"

if [ -f "$CERT_PATH" ] && [ -f "$KEY_PATH" ]; then
    log "读取证书内容"
    CERT_CONTENT=$(cat "$CERT_PATH")
    KEY_CONTENT=$(cat "$KEY_PATH")

    # 调用飞书通知函数
    send_to_feishu "$DOMAIN" "$CERT_CONTENT" "$KEY_CONTENT" "$ENCRYPT_KEY"

    if [ $? -eq 0 ]; then
        log "飞书通知发送成功"
    else
        log "飞书通知发送失败"
    fi
else
    log "错误：未找到证书文件"
fi