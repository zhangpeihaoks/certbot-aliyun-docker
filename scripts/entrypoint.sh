#!/bin/bash

# 加载核心功能
source /usr/local/core_functions/log_manager.sh
source /usr/local/core_functions/aliyun_auth.sh

init_log
log "启动入口脚本..."

# 安全认证阿里云
if ! authenticate_aliyun; then
    log "阿里云认证失败，退出"
    exit 1
fi

# 添加定时任务
if ! crontab -l | grep -q "0 2 * * * /usr/local/bin/get_cert.sh renew >> $LOG_FILE 2>&1"; then
    log "添加CertBot续订任务到crontab"
    echo "0 2 * * * /usr/local/bin/get_cert.sh renew >> $LOG_FILE 2>&1" | crontab -
fi

# 执行证书获取
/usr/local/bin/get_cert.sh >> "$LOG_FILE" 2>&1

# 启动服务
log "启动crond服务..."
crond

# 实时输出日志
log "开始实时日志监控..."
tail -f "$LOG_FILE"