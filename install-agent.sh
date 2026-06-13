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

# گرفتن API Key با حلقه تا خالی نباشد
API_KEY=""
while [ -z "$API_KEY" ]; do
    # استفاده از /dev/tty برای اطمینان از خواندن ورودی در محیط‌های غیرتعاملی
    read -p "Enter Agent API Key: " API_KEY < /dev/tty
    if [ -z "$API_KEY" ]; then
        echo -e "${RED}API Key cannot be empty. Please try again.${NC}"
    fi
done

echo
echo -e "${BLUE}[1/9]${NC} Updating packages..."
apt update

echo -e "${BLUE}[2/9]${NC} Installing dependencies..."
apt install -y \
    python3 \
    python3-venv \
    python3-pip \
    curl \
    gcc \
    python3-dev \
    net-tools

echo -e "${BLUE}[3/9]${NC} Creating application directory..."
mkdir -p /opt/beeny-agent
cd /opt/beeny-agent

echo -e "${BLUE}[4/9]${NC} Creating virtual environment..."
if [ ! -d "venv" ]; then
    python3 -m venv venv
fi

source venv/bin/activate

echo -e "${BLUE}[5/9]${NC} Downloading files..."
curl -fsSL -o agent.py https://raw.githubusercontent.com/Beni-SHL/beeny-agent/main/agent.py || {
    echo -e "${RED}Failed to download agent.py${NC}"
    exit 1
}
curl -fsSL -o requirements.txt https://raw.githubusercontent.com/Beni-SHL/beeny-agent/main/requirements.txt || {
    echo -e "${RED}Failed to download requirements.txt${NC}"
    exit 1
}

echo -e "${BLUE}[6/9]${NC} Installing Python packages..."
pip install --upgrade pip
pip install -r requirements.txt

echo -e "${BLUE}[7/9]${NC} Creating configuration..."
cat > config.py << EOF
AGENT_API_KEY = "$API_KEY"
PORT = 5001
EOF

# بررسی آزاد بودن پورت 5001
if netstat -tuln | grep -q ":5001 "; then
    echo -e "${YELLOW}Warning: Port 5001 is already in use. Agent may fail to start.${NC}"
    read -p "Do you want to change port? (y/n): " change_port < /dev/tty
    if [[ "$change_port" =~ ^[Yy]$ ]]; then
        read -p "Enter new port: " NEW_PORT < /dev/tty
        sed -i "s/PORT = 5001/PORT = $NEW_PORT/" config.py
        echo -e "${GREEN}Port changed to $NEW_PORT${NC}"
    fi
fi

echo -e "${BLUE}[8/9]${NC} Creating systemd service..."
cat > /etc/systemd/system/beeny-agent.service << EOF
[Unit]
Description=Beeny Agent
After=network.target

[Service]
WorkingDirectory=/opt/beeny-agent
ExecStart=/opt/beeny-agent/venv/bin/python /opt/beeny-agent/agent.py
Restart=always
RestartSec=5
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable beeny-agent

echo -e "${BLUE}[9/9]${NC} Starting agent..."
systemctl restart beeny-agent
sleep 5

echo
if systemctl is-active --quiet beeny-agent; then
    echo -e "${GREEN}====================================${NC}"
    echo -e "${GREEN}✓ Installation completed${NC}"
    echo -e "${GREEN}✓ Agent service is running${NC}"
    echo -e "${GREEN}✓ Node is ready${NC}"
    echo -e "${GREEN}====================================${NC}"
    echo -e "${CYAN}Check logs: journalctl -u beeny-agent -f${NC}"
else
    echo -e "${RED}Agent failed to start${NC}"
    echo -e "${YELLOW}Showing service status and last logs:${NC}"
    systemctl status beeny-agent --no-pager
    journalctl -u beeny-agent -n 20 --no-pager
    exit 1
fi
