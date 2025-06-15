## 🚀 安全增强版 Certbot 阿里云 DNS 自动化证书管理

### 主要改进
1. **密钥安全**：不再创建阿里云配置文件，避免密钥泄露
2. **加密增强**：支持任意长度加密密钥，自动转换为安全哈希
3. **智能续订**：仅在证书30天内过期时才续订
4. **日志优化**：统一日志格式，添加时间戳
5. **模块化设计**：核心功能提取为可复用模块

### 新增环境变量
| 变量名 | 说明 | 示例 |
|--------|------|------|
| `ENCRYPT_KEY` | 支持任意字符串，自动转换为加密密钥 | `MySecret123!` |

### 解密示例 (Node.js)
```javascript
const crypto = require('crypto');

function decrypt(encrypted, key, iv) {
  const keyHash = crypto.createHash('sha256')
    .update(key)
    .digest();
    
  const decipher = crypto.createDecipheriv(
    'aes-256-cbc', 
    keyHash, 
    Buffer.from(iv, 'hex')
  );
  
  return Buffer.concat([
    decipher.update(Buffer.from(encrypted, 'base64')),
    decipher.final()
  ]).toString();
}
```

### 运行示例
``` shell
docker run -d \
-e ALIYUN_ACCESS_KEY_ID=your_id \
-e ALIYUN_ACCESS_KEY_SECRET=your_secret \
-e DOMAIN="*.example.com" \
-e EMAIL="admin@example.com" \
-e WEBHOOK_URL="https://your.webhook.url" \
-e ENCRYPT_KEY="MySecurePass123!" \
-v /etc/letsencrypt:/etc/letsencrypt \
jyyqaj/certbot-aliyun-docker
```

### 架构说明
```
├── core_functions    # 可复用核心模块
│   ├── aliyun_auth.sh    # 安全认证
│   ├── feishu_notify.sh  # 通知服务
│   └── log_manager.sh    # 日志管理
├── scripts           # 业务流程
│   ├── entrypoint.sh     # 容器入口
│   ├── get_cert.sh       # 证书管理
│   └── webhook.sh        # 证书回调
└── Dockerfile        # 构建定义
```

### 使用说明

1. **构建镜像**：
```bash
docker build -t certbot-aliyun-docker .
```
