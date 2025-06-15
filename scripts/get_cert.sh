#!/bin/bash

source /usr/local/core_functions/log_manager.sh
init_log

# 检查测试环境标志
if [ "$USE_TEST_ENV" = "true" ]; then
    CERTBOT_FLAGS="--test-cert"
    log "使用测试环境"
else
    CERTBOT_FLAGS=""
fi

# 申请或续订证书
renew_cert() {
    log "开始证书操作流程"

    # 精确检查证书是否存在
    if ! certbot certificates | grep -q "Domains: $DOMAIN"; then
        log "请求新证书: $DOMAIN"
        certbot certonly -d "$DOMAIN" \
            --manual \
            --preferred-challenges dns \
            --manual-auth-hook "alidns" \
            --manual-cleanup-hook "alidns clean" \
            --email "$EMAIL" \
            --agree-tos \
            $CERTBOT_FLAGS \
            --deploy-hook /usr/local/bin/webhook.sh
    else
        log "续订现有证书: $DOMAIN"
        certbot renew \
            --manual \
            --preferred-challenges dns \
            --manual-auth-hook "alidns" \
            --manual-cleanup-hook "alidns clean" \
            --email "$EMAIL" \
            --agree-tos \
            $CERTBOT_FLAGS \
            --deploy-hook /usr/local/bin/webhook.sh
    fi

    if [ $? -ne 0 ]; then
        log "证书操作失败"
        exit 1
    fi
}

# 主逻辑
if [ "$1" = "renew" ]; then
    log "执行证书续订"
    renew_cert
else
    # 检查证书有效期（30天内过期才续订）
    if openssl x509 -checkend 2592000 -noout -in "/etc/letsencrypt/live/${DOMAIN#\*\.}/cert.pem"; then
        log "证书有效期超过30天，跳过续订"
    else
        log "证书即将过期或不存在，开始操作"
        renew_cert
    fi
fi