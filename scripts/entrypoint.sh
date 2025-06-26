#!/bin/bash

echo "启动入口脚本..."

# 配置阿里云 CLI
aliyun configure set --access-key-id "$ALIYUN_ACCESS_KEY_ID" --access-key-secret "$ALIYUN_ACCESS_KEY_SECRET" --region "cn-hangzhou"

LOG_FILE="/var/log/certbot-renew.log"
if [ ! -f "$LOG_FILE" ]; then
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    if [ $? -ne 0 ]; then
        echo "无法创建日志文件 $LOG_FILE，退出脚本"
        exit 1
    fi
fi

# 确保 crontab 目录存在
mkdir -p /var/spool/cron/crontabs
chmod 0700 /var/spool/cron/crontabs

# 检查 get_cert.sh 脚本的存在和权限
GET_CERT_SCRIPT="/usr/local/bin/get_cert.sh"
if [ ! -f "$GET_CERT_SCRIPT" ]; then
    echo "未找到 $GET_CERT_SCRIPT 脚本，退出脚本"
    exit 1
fi
if [ ! -x "$GET_CERT_SCRIPT" ]; then
    chmod +x "$GET_CERT_SCRIPT"
fi

# 检查 webhook.sh 脚本的存在和权限
WEBHOOK_SCRIPT="/usr/local/bin/webhook.sh"
if [ ! -f "$WEBHOOK_SCRIPT" ]; then
    echo "未找到 $WEBHOOK_SCRIPT 脚本，退出脚本"
    exit 1
fi
if [ ! -x "$WEBHOOK_SCRIPT" ]; then
    chmod +x "$WEBHOOK_SCRIPT"
fi

# 添加 CertBot 续订任务到 crontab
CERT_RENEW_TASK="0 2 * * * /usr/local/bin/get_cert.sh renew >> $LOG_FILE 2>&1"
if ! crontab -l 2>/dev/null | grep -q "$CERT_RENEW_TASK"; then
    echo "将 CertBot 续订任务添加到 crontab..." >> $LOG_FILE
    (crontab -l 2>/dev/null; echo "$CERT_RENEW_TASK") | crontab -
    if [ $? -ne 0 ]; then
        echo "无法添加 CertBot 续订任务到 crontab，退出脚本"
        exit 1
    fi
fi

# 添加每日证书检查任务
CERT_CHECK_TASK="0 8 * * * /usr/local/bin/webhook.sh check >> $LOG_FILE 2>&1"
if ! crontab -l 2>/dev/null | grep -q "$CERT_CHECK_TASK"; then
    echo "添加每日证书检查任务到 crontab..." >> $LOG_FILE
    (crontab -l 2>/dev/null; echo "$CERT_CHECK_TASK") | crontab -
    if [ $? -ne 0 ]; then
        echo "无法添加每日证书检查任务到 crontab，退出脚本"
        exit 1
    fi
fi

# 提取主域名（去掉通配符*）
BASE_DOMAIN=${DOMAIN#\*\.}
if [ "$DOMAIN" = "$BASE_DOMAIN" ]; then
    # 如果没有通配符，直接使用原域名
    BASE_DOMAIN=$DOMAIN
fi

# 检查证书是否存在
CERT_DIR="/etc/letsencrypt/live/$BASE_DOMAIN"
if [ ! -d "$CERT_DIR" ] || [ ! -f "$CERT_DIR/fullchain.pem" ] || [ ! -f "$CERT_DIR/privkey.pem" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') 未找到证书，开始申请新证书..." >> $LOG_FILE

    # 调用 get_cert.sh 申请新证书
    /usr/local/bin/get_cert.sh >> $LOG_FILE 2>&1

    # 检查申请结果
    if [ $? -ne 0 ] || [ ! -f "$CERT_DIR/fullchain.pem" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') 证书申请失败" >> $LOG_FILE
        # 发送错误通知
        /usr/local/bin/webhook.sh check >> $LOG_FILE 2>&1
    fi
fi

# 启动 crond 服务并保持容器运行，同时输出日志
echo "启动 crond 服务..." >> $LOG_FILE
crond

# 执行一次初始证书检查
echo "执行初始证书检查..." >> $LOG_FILE
/usr/local/bin/webhook.sh check >> $LOG_FILE 2>&1

# 实时输出日志
tail -f $LOG_FILE