#!/bin/bash

LOG_FILE="/var/log/certbot-renew.log"

[ ! -f "$LOG_FILE" ] && touch "$LOG_FILE"

# 提取主域名（去掉通配符*）
BASE_DOMAIN=${DOMAIN#\*\.}
if [ "$DOMAIN" = "$BASE_DOMAIN" ]; then
    # 如果没有通配符，直接使用原域名
    BASE_DOMAIN=$DOMAIN
fi

# 确定证书路径
if [ "$1" = "check" ] || [ -z "$RENEWED_LINEAGE" ]; then
    # 检查模式或非续订模式
    CERT_PATH="/etc/letsencrypt/live/$BASE_DOMAIN/fullchain.pem"
    KEY_PATH="/etc/letsencrypt/live/$BASE_DOMAIN/privkey.pem"
else
    # 续订模式
    CERT_PATH="$RENEWED_LINEAGE/fullchain.pem"
    KEY_PATH="$RENEWED_LINEAGE/privkey.pem"
fi

# 获取证书信息函数
get_cert_info() {
    local cert_path="$1"
    local domain="$2"

    # 检查证书文件是否存在
    if [ ! -f "$cert_path" ]; then
        echo "❌ 错误：证书文件不存在"
        return 1
    fi

    # 获取证书信息
    END_DATE=$(openssl x509 -enddate -noout -in "$cert_path" 2>/dev/null | cut -d= -f2)
    SERIAL=$(openssl x509 -serial -noout -in "$cert_path" 2>/dev/null | cut -d= -f2)
    ISSUER=$(openssl x509 -issuer -noout -in "$cert_path" 2>/dev/null | sed 's/issuer= //')

    # 检查是否成功获取信息
    if [ -z "$END_DATE" ]; then
        echo "❌ 错误：无法读取证书信息"
        return 1
    fi

    # 计算剩余天数
    end_epoch=$(date -d "$END_DATE" +%s 2>/dev/null)
    now_epoch=$(date +%s)

    if [ -z "$end_epoch" ]; then
        DAYS_LEFT="未知"
        STATUS="⚠️ 无法确定有效期"
    else
        DAYS_LEFT=$(( (end_epoch - now_epoch) / 86400 ))

        # 根据剩余天数设置状态
        if [ $DAYS_LEFT -lt 0 ]; then
            STATUS="❌ 已过期 ($((-DAYS_LEFT)) 天前)"
        elif [ $DAYS_LEFT -lt 7 ]; then
            STATUS="⚠️ 即将过期 ($DAYS_LEFT 天后)"
        elif [ $DAYS_LEFT -lt 30 ]; then
            STATUS="🟡 即将到期 ($DAYS_LEFT 天后)"
        else
            STATUS="✅ 有效 ($DAYS_LEFT 天后)"
        fi
    fi

    # 构建消息
    MESSAGE="SSL证书状态: $STATUS\n域名: $domain\n有效期至: $END_DATE"

    # 添加序列号和颁发者（如果可用）
    [ -n "$SERIAL" ] && MESSAGE="$MESSAGE\n序列号: $SERIAL"
    [ -n "$ISSUER" ] && MESSAGE="$MESSAGE\n颁发机构: $ISSUER"

    echo -e "$MESSAGE"
}

# 发送通知函数
send_notification() {
    local message="$1"
    local event_type="$2"

    # 清理消息中的特殊字符
    CLEAN_MESSAGE=$(echo "$message" | sed 's/"/\\"/g' | sed "s/'/\\\'/g" | tr -d '\n' | tr -d '\r')

    # 构建飞书消息
    JSON_PAYLOAD='{
        "msg_type": "text",
        "content": {
            "text": "'"$CLEAN_MESSAGE"'"
        }
    }'

    # 打印调试信息
    echo "发送通知到飞书: $JSON_PAYLOAD" >> "$LOG_FILE"

    # 发送通知
    RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
        -d "$JSON_PAYLOAD" \
        "$WEBHOOK_URL")

    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$TIMESTAMP [$event_type] 飞书响应: $RESPONSE" >> "$LOG_FILE"

    # 检查响应
    if echo "$RESPONSE" | grep -q '"StatusCode":0'; then
        echo "$TIMESTAMP [$event_type] 飞书通知已发送" >> "$LOG_FILE"
    else
        echo "$TIMESTAMP [$event_type] 飞书通知发送失败: $RESPONSE" >> "$LOG_FILE"
    fi
}

# 主逻辑
if [ -f "$CERT_PATH" ] && [ -f "$KEY_PATH" ]; then
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$TIMESTAMP 找到证书文件，准备发送通知" >> "$LOG_FILE"

    # 获取证书信息
    MESSAGE=$(get_cert_info "$CERT_PATH" "$DOMAIN")

    # 确定事件类型
    if [ "$1" = "check" ]; then
        EVENT_TYPE="每日检查"
        MESSAGE="ℹ️ 证书状态检查\n$MESSAGE"
    elif [ -n "$RENEWED_LINEAGE" ]; then
        EVENT_TYPE="证书更新"
        MESSAGE="🎉 证书已成功更新！\n$MESSAGE"
    else
        EVENT_TYPE="证书检查"
        MESSAGE="ℹ️ 证书状态检查\n$MESSAGE"
    fi

    # 发送通知
    send_notification "$MESSAGE" "$EVENT_TYPE"

else
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$TIMESTAMP 错误：未找到证书文件" >> "$LOG_FILE"

    # 发送错误通知
    MESSAGE="❌ 错误：未找到证书文件\n域名: $DOMAIN\n路径: $CERT_PATH\n请检查证书申请流程"
    send_notification "$MESSAGE" "证书错误"
fi