#!/bin/bash

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

clear

echo -e "${CYAN}"
echo "██████╗ ███████╗███████╗███╗   ██╗██╗   ██╗"
echo "██╔══██╗██╔════╝██╔════╝████╗  ██║╚██╗ ██╔╝"
echo "██████╔╝█████╗  █████╗  ██╔██╗ ██║ ╚████╔╝ "
echo "██╔══██╗██╔══╝  ██╔══╝  ██║╚██╗██║  ╚██╔╝  "
echo "██████╔╝███████╗███████╗██║ ╚████║   ██║   "
echo "╚═════╝ ╚══════╝╚══════╝╚═╝  ╚═══╝   ╚═╝   "
echo -e "${NC}"

echo -e "${GREEN}====================================${NC}"
echo -e "${GREEN}      Beeny Agent Installer${NC}"
echo -e "${GREEN}====================================${NC}"
echo

if [ "$EUID" -ne 0 ]; then
echo -e "${RED}Please run as root${NC}"
exit 1
fi

read -p "Enter Agent API Key: " API_KEY

echo
echo -e "${BLUE}[1/8]${NC} Updating packages..."
apt update

echo -e "${BLUE}[2/8]${NC} Installing dependencies..."
apt install -y 
python3 
python3-venv 
python3-pip 
curl

echo -e "${BLUE}[3/8]${NC} Creating application directory..."
mkdir -p /opt/beeny-agent

cd /opt/beeny-agent

echo -e "${BLUE}[4/8]${NC} Creating virtual environment..."
if [ ! -d "venv" ]; then
python3 -m venv venv
fi

source venv/bin/activate

echo -e "${BLUE}[5/8]${NC} Downloading files..."
curl -fsSL -o agent.py https://raw.githubusercontent.com/Beni-SHL/beeny-agent/main/agent.py
curl -fsSL -o requirements.txt https://raw.githubusercontent.com/Beni-SHL/beeny-agent/main/requirements.txt

echo -e "${BLUE}[6/8]${NC} Installing Python packages..."
pip install --upgrade pip
pip install -r requirements.txt

echo -e "${BLUE}[7/8]${NC} Creating configuration..."
cat > config.py << EOF
AGENT_API_KEY = "$API_KEY"
PORT = 5001
EOF

echo -e "${BLUE}[8/8]${NC} Creating systemd service..."
cat > /etc/systemd/system/beeny-agent.service << EOF
[Unit]
Description=Beeny Agent
After=network.target

[Service]
WorkingDirectory=/opt/beeny-agent
ExecStart=/opt/beeny-agent/venv/bin/python /opt/beeny-agent/agent.py
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable beeny-agent
systemctl restart beeny-agent

sleep 3

echo

if systemctl is-active --quiet beeny-agent; then
echo -e "${GREEN}====================================${NC}"
echo -e "${GREEN}✓ Installation completed${NC}"
echo -e "${GREEN}✓ Agent service is running${NC}"
echo -e "${GREEN}✓ Node is ready${NC}"
echo -e "${GREEN}====================================${NC}"
else
echo -e "${RED}Agent failed to start${NC}"
systemctl status beeny-agent --no-pager
exit 1
fi
