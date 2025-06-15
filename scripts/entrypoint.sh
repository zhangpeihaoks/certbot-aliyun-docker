#!/bin/bash

echo "启动入口脚本..."

# 配置阿里云 CLI
aliyun configure set --access-key-id "$ALIYUN_ACCESS_KEY_ID" --access-key-secret "$ALIYUN_ACCESS_KEY_SECRET" --region "cn-hangzhou"

LOG_FILE="/var/log/certbot-renew.log"

# 判断日志文件是否存在，不存在则创建
if [ ! -f "$LOG_FILE" ]; then
    touch $LOG_FILE
fi

# 确保 crontab 目录存在
mkdir -p /var/spool/cron/crontabs
chmod 0700 /var/spool/cron/crontabs

# 添加 CertBot 续订任务到 crontab
if ! crontab -l 2>/dev/null | grep -q "0 2 * * * /usr/local/bin/get_cert.sh renew >> $LOG_FILE 2>&1"; then
    echo "将 CertBot 续订任务添加到 crontab..." >> $LOG_FILE
    echo "0 2 * * * /usr/local/bin/get_cert.sh renew >> $LOG_FILE 2>&1" | crontab -
fi

# 添加每日证书检查任务
if ! crontab -l 2>/dev/null | grep -q "0 8 * * * /usr/local/bin/webhook.sh check >> $LOG_FILE 2>&1"; then
    echo "添加每日证书检查任务到 crontab..." >> $LOG_FILE
    (crontab -l 2>/dev/null; echo "0 8 * * * /usr/local/bin/webhook.sh check >> $LOG_FILE 2>&1") | crontab -
fi

/usr/local/bin/get_cert.sh >> $LOG_FILE 2>&1

# 启动 crond 服务并保持容器运行，同时输出日志
echo "启动 crond 服务..." >> $LOG_FILE
crond

# 执行一次初始证书检查
echo "执行初始证书检查..." >> $LOG_FILE
/usr/local/bin/webhook.sh check >> $LOG_FILE 2>&1

# 实时输出日志
tail -f $LOG_FILE