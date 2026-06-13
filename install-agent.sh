#!/bin/bash

set -e

echo "Installing Beeny Agent..."

apt update

apt install -y \
    python3 \
    python3-venv \
    python3-pip \
    curl

mkdir -p /opt/beeny-agent

cd /opt/beeny-agent

if [ ! -d "venv" ]; then
    python3 -m venv venv
fi

source venv/bin/activate

pip install --upgrade pip
pip install flask requests

curl -o agent.py https://raw.githubusercontent.com/Beni-SHL/beeny-agent/main/agent.py
curl -o config.py https://raw.githubusercontent.com/Beni-SHL/beeny-agent/main/config.py.example

cat >/etc/systemd/system/beeny-agent.service <<EOF
[Unit]
Description=Beeny Agent
After=network.target

[Service]
WorkingDirectory=/opt/beeny-agent
ExecStart=/opt/beeny-agent/venv/bin/python /opt/beeny-agent/agent.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable beeny-agent
systemctl restart beeny-agent

echo "Beeny Agent Installed Successfully"
