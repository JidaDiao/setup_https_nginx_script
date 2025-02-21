#!/bin/bash

# 检查是否以 root 用户运行
if [ "$EUID" -ne 0 ]; then
  echo "请以 root 用户运行此脚本。"
  exit 1
fi

# 用户输入参数
read -p "请输入域名 (如 example.example.com): " DOMAIN
read -p "请输入服务器转发地址 (如 localhost): " SERVER_ADDR
read -p "请输入服务器转发端口 (如 3000): " SERVER_PORT
read -p "是否有公网 IP? (yes/no): " PUBLIC_IP

# 配置路径
NGINX_AVAILABLE_DIR="/etc/nginx/sites-available"
NGINX_ENABLED_DIR="/etc/nginx/sites-enabled"
NGINX_CONF_FILE="${NGINX_AVAILABLE_DIR}/${DOMAIN}"

# 检查域名有效性
if [[ -z "$DOMAIN" || -z "$SERVER_ADDR" || -z "$SERVER_PORT" ]]; then
  echo "域名、服务器地址或端口不能为空。请检查输入。"
  exit 1
fi

# 利用 Certbot 申请 SSL 证书
echo "正在使用 Certbot 获取 TLS/SSL 证书..."
sudo certbot certonly --nginx -d $DOMAIN

# 检查证书文件是否成功创建
CERT_DIR="/etc/letsencrypt/live/${DOMAIN}"
if [ ! -f "${CERT_DIR}/fullchain.pem" ] || [ ! -f "${CERT_DIR}/privkey.pem" ]; then
  echo "证书申请失败，请检查 Certbot 输出。"
  exit 1
fi
echo "证书成功获取，存放于 ${CERT_DIR}"

# 创建 Nginx 配置文件
cat > $NGINX_CONF_FILE <<EOL
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$server_name\$request_uri;  # 强制重定向所有 HTTP 请求到 HTTPS
}

server {
    listen 443 ssl http2;  # 监听 443 端口,并启用 SSL 和 HTTP/2
    server_name $DOMAIN;

    # 使用 Certbot 获取的证书
    ssl_certificate     ${CERT_DIR}/fullchain.pem;
    ssl_certificate_key ${CERT_DIR}/privkey.pem;
    ssl_stapling on;
    ssl_stapling_verify on;

    # 设置最大请求体大小
    client_max_body_size 1000m;

    location / {
        proxy_pass http://${SERVER_ADDR}:${SERVER_PORT};  # 将请求转发到本地服务
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOL

# 检查并创建符号链接
if [ ! -L "${NGINX_ENABLED_DIR}/${DOMAIN}" ]; then
  sudo ln -s $NGINX_CONF_FILE "${NGINX_ENABLED_DIR}/${DOMAIN}"
  echo "已创建符号链接：${NGINX_ENABLED_DIR}/${DOMAIN}"
else
  echo "符号链接已存在：${NGINX_ENABLED_DIR}/${DOMAIN}"
fi

# 测试 Nginx 配置
echo "测试 Nginx 配置..."
if sudo nginx -t; then
  echo "配置测试通过，重新启动 Nginx 服务..."
  sudo systemctl restart nginx
  echo "Nginx 服务已重启。"
else
  echo "Nginx 配置测试失败，请检查错误信息。"
  exit 1
fi

# 提示用户检查公网 IP
echo "脚本执行完成。请确保域名已正确指向服务器的公网 IP。"
if [[ $PUBLIC_IP != "yes" ]]; then
  echo "检测到此服务器没有公网 IP，请确保域名解析到正确的代理服务器。"
fi

exit 0
