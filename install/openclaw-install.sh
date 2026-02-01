#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: ludicrypt
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/openclaw/openclaw

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing system dependencies"
$STD apt-get install -y \
  curl \
  wget \
  gnupg \
  ca-certificates \
  openssl \
  nginx
msg_ok "Installed system dependencies"

msg_info "Installing Node.js 22"
curl -fsSL https://deb.nodesource.com/setup_22.x | $STD bash -
$STD apt-get install -y nodejs
msg_ok "Installed Node.js $(node -v)"

DOCKER_LATEST_VERSION=$(get_latest_github_release "moby/moby")
msg_info "Installing Docker $DOCKER_LATEST_VERSION"
DOCKER_CONFIG_PATH='/etc/docker/daemon.json'
mkdir -p "$(dirname "$DOCKER_CONFIG_PATH")"
cat <<'EOF' >"$DOCKER_CONFIG_PATH"
{
  "log-driver": "journald",
  "storage-driver": "overlay2"
}
EOF
$STD sh <(curl -fsSL https://get.docker.com)
$STD systemctl enable --now docker
msg_ok "Installed Docker $DOCKER_LATEST_VERSION"

msg_info "Installing OpenClaw"
$STD npm install -g openclaw@latest
msg_ok "Installed OpenClaw $(openclaw --version 2>/dev/null || echo '')"

msg_info "Configuring OpenClaw"
mkdir -p /etc/openclaw /var/lib/openclaw

cat <<'EOF' >/usr/lib/systemd/system/openclaw.service
[Unit]
Description=OpenClaw AI Gateway
After=network.target docker.service
Wants=docker.service

[Service]
Type=simple
ExecStart=/usr/bin/openclaw serve --host 127.0.0.1 --port 18789
Restart=on-failure
RestartSec=5
Environment=HOME=/root
WorkingDirectory=/var/lib/openclaw

[Install]
WantedBy=multi-user.target
EOF

$STD systemctl daemon-reload
$STD systemctl enable --now openclaw
msg_ok "Configured OpenClaw"

msg_info "Generating self-signed TLS certificate"
mkdir -p /etc/nginx/ssl
openssl req -x509 -nodes -days 3650 \
  -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/openclaw.key \
  -out /etc/nginx/ssl/openclaw.crt \
  -subj "/CN=openclaw" \
  2>/dev/null
msg_ok "Generated self-signed TLS certificate"

msg_info "Configuring Nginx reverse proxy"
cat <<'EOF' >/etc/nginx/sites-available/openclaw
# OpenClaw reverse proxy configuration
# Replace the self-signed certificate with Let's Encrypt for production use:
#   apt install certbot python3-certbot-nginx
#   certbot --nginx -d your.domain.com

server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    server_name _;

    ssl_certificate /etc/nginx/ssl/openclaw.crt;
    ssl_certificate_key /etc/nginx/ssl/openclaw.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    location / {
        proxy_pass http://127.0.0.1:18789;
        proxy_http_version 1.1;

        # WebSocket support
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Long timeouts for persistent connections
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }
}
EOF

rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/openclaw /etc/nginx/sites-enabled/openclaw
$STD nginx -t
$STD systemctl restart nginx
msg_ok "Configured Nginx reverse proxy"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned up"
