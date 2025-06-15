FROM alpine:3.18

# 安装基础工具
RUN apk add --no-cache \
    bash \
    curl \
    jq \
    certbot \
    bind-tools \
    openssl \
    coreutils

# 安装阿里云CLI
RUN wget https://aliyuncli.alicdn.com/aliyun-cli-linux-latest-amd64.tgz -O /tmp/aliyun.tgz && \
    tar xzvf /tmp/aliyun.tgz -C /usr/local/bin && \
    rm /tmp/aliyun.tgz && \
    chmod +x /usr/local/bin/aliyun

# 安装Certbot DNS插件
RUN wget https://cdn.jsdelivr.net/gh/justjavac/certbot-dns-aliyun@main/alidns.sh -O /usr/local/bin/alidns && \
    chmod +x /usr/local/bin/alidns

# 创建核心函数目录
RUN mkdir -p /usr/local/core_functions

# 复制核心功能
COPY core_functions/* /usr/local/core_functions/
RUN chmod +x /usr/local/core_functions/*

# 复制脚本
COPY scripts/* /usr/local/bin/
RUN chmod +x /usr/local/bin/*

# 设置工作目录和入口点
WORKDIR /app
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# 创建必要的目录
RUN mkdir -p /var/spool/cron/crontabs && \
    touch /var/spool/cron/crontabs/root && \
    mkdir -p /var/log