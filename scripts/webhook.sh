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

    # 返回结构化信息
    echo "STATUS:$STATUS"
    echo "DOMAIN:$domain"
    echo "END_DATE:$END_DATE"
    echo "SERIAL:$SERIAL"
    echo "ISSUER:$ISSUER"
    echo "DAYS_LEFT:$DAYS_LEFT"
}

# 构建飞书富文本消息
build_feishu_message() {
    local event_type="$1"
    local status="$2"
    local domain="$3"
    local end_date="$4"
    local serial="$5"
    local issuer="$6"
    local days_left="$7"

    # 根据事件类型设置标题
    case "$event_type" in
        "证书更新")
            title="SSL证书已更新"
            ;;
        "每日检查")
            title="SSL证书状态检查"
            ;;
        "证书错误")
            title="SSL证书错误"
            ;;
        *)
            title="SSL证书通知"
            ;;
    esac

    # 构建消息内容
    cat <<EOF
{
    "msg_type": "post",
    "content": {
        "post": {
            "zh_cn": {
                "title": "$title",
                "content": [
                    [
                        {
                            "tag": "text",
                            "text": "状态: "
                        },
                        {
                            "tag": "text",
                            "text": "$status"
                        }
                    ],
                    [
                        {
                            "tag": "text",
                            "text": "域名: "
                        },
                        {
                            "tag": "text",
                            "text": "$domain"
                        }
                    ],
                    [
                        {
                            "tag": "text",
                            "text": "有效期: "
                        },
                        {
                            "tag": "text",
                            "text": "$end_date"
                        }
                    ],
                    [
                        {
                            "tag": "text",
                            "text": "剩余天数: "
                        },
                        {
                            "tag": "text",
                            "text": "$days_left"
                        }
                    ],
                    [
                        {
                            "tag": "text",
                            "text": "序列号: "
                        },
                        {
                            "tag": "text",
                            "text": "$serial"
                        }
                    ],
                    [
                        {
                            "tag": "text",
                            "text": "颁发机构: "
                        },
                        {
                            "tag": "text",
                            "text": "$issuer"
                        }
                    ],
                    [
                        {
                            "tag": "text",
                            "text": "操作: "
                        },
                        {
                            "tag": "a",
                            "text": "查看证书",
                            "href": "https://crt.sh/?q=$domain"
                        }
                    ]
                ]
            }
        }
    }
}
EOF
}

# 发送通知函数
send_notification() {
    local json_payload="$1"
    local event_type="$2"

    # 打印调试信息
    echo "发送通知到飞书: $json_payload" >> "$LOG_FILE"

    # 发送通知
    RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
        -d "$json_payload" \
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
    CERT_INFO=$(get_cert_info "$CERT_PATH" "$DOMAIN")

    # 解析证书信息
    STATUS=$(echo "$CERT_INFO" | grep "^STATUS:" | cut -d: -f2-)
    DOMAIN_VALUE=$(echo "$CERT_INFO" | grep "^DOMAIN:" | cut -d: -f2-)
    END_DATE=$(echo "$CERT_INFO" | grep "^END_DATE:" | cut -d: -f2-)
    SERIAL=$(echo "$CERT_INFO" | grep "^SERIAL:" | cut -d: -f2-)
    ISSUER=$(echo "$CERT_INFO" | grep "^ISSUER:" | cut -d: -f2-)
    DAYS_LEFT=$(echo "$CERT_INFO" | grep "^DAYS_LEFT:" | cut -d: -f2-)

    # 确定事件类型
    if [ "$1" = "check" ]; then
        EVENT_TYPE="每日检查"
    elif [ -n "$RENEWED_LINEAGE" ]; then
        EVENT_TYPE="证书更新"
    else
        EVENT_TYPE="证书检查"
    fi

    # 构建飞书消息
    JSON_PAYLOAD=$(build_feishu_message "$EVENT_TYPE" "$STATUS" "$DOMAIN_VALUE" "$END_DATE" "$SERIAL" "$ISSUER" "$DAYS_LEFT")

    # 发送通知
    send_notification "$JSON_PAYLOAD" "$EVENT_TYPE"

else
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$TIMESTAMP 错误：未找到证书文件" >> "$LOG_FILE"

    # 构建错误消息
    ERROR_JSON=$(cat <<EOF
{
    "msg_type": "post",
    "content": {
        "post": {
            "zh_cn": {
                "title": "SSL证书错误",
                "content": [
                    [
                        {
                            "tag": "text",
                            "text": "错误: "
                        },
                        {
                            "tag": "text",
                            "text": "未找到证书文件"
                        }
                    ],
                    [
                        {
                            "tag": "text",
                            "text": "域名: "
                        },
                        {
                            "tag": "text",
                            "text": "$DOMAIN"
                        }
                    ],
                    [
                        {
                            "tag": "text",
                            "text": "路径: "
                        },
                        {
                            "tag": "text",
                            "text": "$CERT_PATH"
                        }
                    ],
                    [
                        {
                            "tag": "text",
                            "text": "操作: "
                        },
                        {
                            "tag": "a",
                            "text": "检查证书服务",
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

    # 发送错误通知
    send_notification "$ERROR_JSON" "证书错误"
fi