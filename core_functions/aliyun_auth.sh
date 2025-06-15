#!/bin/bash

# 安全认证方式，避免创建配置文件
authenticate_aliyun() {
    # 临时设置环境变量
    export ALIYUN_ACCESS_KEY_ID ALIYUN_ACCESS_KEY_SECRET

    # 验证凭据是否有效
    if ! aliyun sts GetCallerIdentity >/dev/null 2>&1; then
        log "阿里云认证失败"
        return 1
    fi

    log "阿里云认证成功"
    return 0
}