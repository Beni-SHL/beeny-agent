#!/bin/bash

C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_CYAN='\033[0;36m'
C_YELLOW='\033[1;33m'
C_PURPLE='\033[0;35m'
C_NC='\033[0m'
BOLD='\033[1m'

clear
echo -e "${C_CYAN}${BOLD}  ____  ______ ______ _   _ __     __"
echo " |  _ \|  ____|  ____| \ | |\ \   / /"
echo " | |_) | |__  | |__  |  \| | \ \_/ / "
echo " |  _ <|  __| |  __| | . \` |  \   /  "
echo " | |_) | |____| |____| |\  |   | |   "
echo " |____/|______|______|_| \_|   |_|   ${C_NC}"
echo -e "${C_PURPLE}${BOLD}✦✦✦ BEENY NODE AGENT AUTO-INSTALLER ✦✦✦${C_NC}\n"

if [ "$EUID" -ne 0 ]; then
    echo -e "${C_RED}❌ Error: Please run as root!${C_NC}"
    exit 1
fi

# ================= پرسش از کاربر =================
echo -e "${C_CYAN}╭────────────────────────────────────────────────────────╮${C_NC}"
echo -e "${C_CYAN}│${C_NC} ${BOLD}Node Configuration Setup${C_NC}                               ${C_CYAN}│${C_NC}"
echo -e "${C_CYAN}╰────────────────────────────────────────────────────────╯${C_NC}"

read -p "🌐 Enter Domain (Leave empty to use Auto IP): " USER_DOMAIN
read -p "🔌 Enter Port (Press Enter for default 5001): " USER_PORT

USER_PORT=${USER_PORT:-5001}

if [ -z "$USER_DOMAIN" ]; then
    SERVER_IP=$(curl -s https://api.ipify.org || echo "YOUR_SERVER_IP")
    NODE_ADDRESS=$SERVER_IP
else
    NODE_ADDRESS=$USER_DOMAIN
fi
echo -e "\n${C_GREEN}✔ Configuration Saved. Starting Installation...${C_NC}\n"
# ===================================================

echo -ne "${C_YELLOW}➜ [1/6] Installing Dependencies (OpenVPN, Python)... ${C_NC}"
export DEBIAN_FRONTEND=noninteractive
apt-get remove -y needrestart > /dev/null 2>&1 || true
apt-get update -y > /dev/null 2>&1
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections 2>/dev/null || true
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections 2>/dev/null || true
apt-get install -y -q -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" openvpn python3 python3-pip iptables iptables-persistent net-tools curl > /dev/null 2>&1
pip3 install flask requests --break-system-packages > /dev/null 2>&1 || pip3 install flask requests > /dev/null 2>&1
echo -e "${C_GREEN}✔ Done${C_NC}"

echo -ne "${C_YELLOW}➜ [2/6] Configuring Network Routing (NAT)... ${C_NC}"
echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-beeny-vpn.conf
sysctl -p /etc/sysctl.d/99-beeny-vpn.conf > /dev/null 2>&1
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n 1)
if [ -n "$INTERFACE" ]; then
    iptables -t nat -A POSTROUTING -o "$INTERFACE" -j MASQUERADE || true
    iptables-save > /etc/iptables/rules.v4 || true
    netfilter-persistent save > /dev/null 2>&1 || true
fi
echo -e "${C_GREEN}✔ Done${C_NC}"

echo -ne "${C_YELLOW}➜ [3/6] Setting up Directories & Config... ${C_NC}"
mkdir -p /opt/beeny-agent /etc/openvpn/server /etc/openvpn/users
API_KEY=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)

cat << EOF > /opt/beeny-agent/config.py
AGENT_API_KEY = "$API_KEY"
AGENT_PORT = $USER_PORT
AGENT_HOST = "$NODE_ADDRESS"
EOF
echo -e "${C_GREEN}✔ Done${C_NC}"

echo -ne "${C_YELLOW}➜ [4/6] Writing Agent Script... ${C_NC}"
cat << 'EOF' > /opt/beeny-agent/agent.py
from flask import Flask, request, jsonify
from config import AGENT_API_KEY, AGENT_PORT
import subprocess
import os

app = Flask(__name__)

def verify_api_key():
    auth = request.headers.get("Authorization", "")
    if not auth.startswith("Bearer "): return False
    return auth.replace("Bearer ", "") == AGENT_API_KEY

@app.route("/api/node/stats")
def stats():
    if not verify_api_key(): return jsonify({"error": "Unauthorized"}), 401
    return jsonify({"status": "online"})

@app.route("/api/node/bootstrap-openvpn", methods=["POST"])
def bootstrap_openvpn():
    if not verify_api_key(): return jsonify({"error": "Unauthorized"}), 401
    data = request.get_json()
    try:
        if data.get("ca_crt"):
            with open("/etc/openvpn/ca.crt", "w") as f: f.write(data.get("ca_crt"))
        if data.get("ta_key"):
            with open("/etc/openvpn/ta.key", "w") as f: f.write(data.get("ta_key"))
        if data.get("server_crt"):
            with open("/etc/openvpn/server/server.crt", "w") as f: f.write(data.get("server_crt"))
        if data.get("server_key"):
            with open("/etc/openvpn/server/server.key", "w") as f: f.write(data.get("server_key"))
        if data.get("server_conf"):
            with open("/etc/openvpn/server/server.conf", "w") as f: f.write(data.get("server_conf"))
        subprocess.run(["systemctl", "restart", "openvpn-server@server"], check=False)
        return jsonify({"success": True, "message": "Bootstrap completed"})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@app.route("/api/node/install-cert", methods=["POST"])
def install_cert():
    if not verify_api_key(): return jsonify({"error": "Unauthorized"}), 401
    data = request.get_json()
    username = data.get("username")
    if not username or "/" in username or ".." in username: return jsonify({"error": "invalid"}), 400
    try:
        with open(f"/etc/openvpn/users/{username}.crt", "w") as f: f.write(data.get("cert"))
        with open(f"/etc/openvpn/users/{username}.key", "w") as f: f.write(data.get("key"))
        return jsonify({"success": True})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=AGENT_PORT)
EOF
echo -e "${C_GREEN}✔ Done${C_NC}"

echo -ne "${C_YELLOW}➜ [5/6] Starting Systemd Service... ${C_NC}"
cat << 'EOF' > /etc/systemd/system/beeny-agent.service
[Unit]
Description=Beeny Node Agent
After=network.target

[Service]
User=root
WorkingDirectory=/opt/beeny-agent
ExecStart=/usr/bin/python3 /opt/beeny-agent/agent.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload > /dev/null 2>&1
systemctl enable --now beeny-agent > /dev/null 2>&1
echo -e "${C_GREEN}✔ Done${C_NC}"

echo -ne "${C_YELLOW}➜ [6/6] Creating Node Manager Menu... ${C_NC}"
cat << 'EOF' > /usr/local/bin/beeny
#!/bin/bash
clear
API=$(grep AGENT_API_KEY /opt/beeny-agent/config.py | cut -d'"' -f2)
PORT=$(grep AGENT_PORT /opt/beeny-agent/config.py | cut -d'=' -f2 | tr -d ' ')
HOST=$(grep AGENT_HOST /opt/beeny-agent/config.py | cut -d'"' -f2)

echo -e "\033[0;36m====================================\033[0m"
echo -e "\033[1m  🛡️  Beeny Node Agent Menu\033[0m"
echo -e "\033[0;36m====================================\033[0m"
echo -e "1. 🔑 Show Connection Info (API Key)"
echo -e "2. 🔌 Change Port"
echo -e "3. 🌐 Change Domain/IP"
echo -e "4. 🔄 Restart Agent Service"
echo -e "5. ❌ Exit"
echo -e "------------------------------------"
read -p "Select an option [1-5]: " opt

case $opt in
    1)
        echo -e "\n\033[0;32mAddress  :\033[0m $HOST"
        echo -e "\033[0;32mPort     :\033[0m $PORT"
        echo -e "\033[0;32mAPI Key  :\033[0m $API\n"
        ;;
    2)
        read -p "Enter new port: " newp
        sed -i "s/AGENT_PORT = .*/AGENT_PORT = $newp/" /opt/beeny-agent/config.py
        systemctl restart beeny-agent
        echo -e "\033[0;32m✔ Port changed to $newp and service restarted!\033[0m"
        ;;
    3)
        read -p "Enter new Domain/IP: " newd
        sed -i "s/AGENT_HOST = .*/AGENT_HOST = \"$newd\"/" /opt/beeny-agent/config.py
        echo -e "\033[0;32m✔ Domain updated! (Change it in Master Panel as well)\033[0m"
        ;;
    4)
        systemctl restart beeny-agent
        echo -e "\033[0;32m✔ Agent Restarted Successfully!\033[0m"
        ;;
    5) exit 0 ;;
    *) echo "Invalid option" ;;
esac
EOF
chmod +x /usr/local/bin/beeny
echo -e "${C_GREEN}✔ Done${C_NC}"

echo -e "\n${C_GREEN}${BOLD}🎉 Installation Completed Successfully!${C_NC}"
echo -e "${C_CYAN}╭────────────────────────────────────────────────────────╮${C_NC}"
echo -e "${C_CYAN}│${C_NC}  ${C_PURPLE}Add this Node to your Beeny Central Panel:${C_NC}            ${C_CYAN}│${C_NC}"
echo -e "${C_CYAN}│${C_NC}  ${BOLD}Address    :${C_NC} ${C_YELLOW}$NODE_ADDRESS${C_NC}                             ${C_CYAN}│${C_NC}"
echo -e "${C_CYAN}│${C_NC}  ${BOLD}Port       :${C_NC} $USER_PORT                                     ${C_CYAN}│${C_NC}"
echo -e "${C_CYAN}│${C_NC}  ${BOLD}API Key    :${C_NC} ${C_GREEN}$API_KEY${C_NC} ${C_CYAN}│${C_NC}"
echo -e "${C_CYAN}╰────────────────────────────────────────────────────────╯${C_NC}"
echo -e "${C_YELLOW}💡 Tip: Type ${BOLD}'beeny'${C_NC}${C_YELLOW} anytime in this terminal to open the manager menu.${C_NC}\n"
