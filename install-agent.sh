#!/bin/bash
set -e

# --- Colors & Styles ---
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_BLUE='\033[0;34m'
C_CYAN='\033[0;36m'
C_YELLOW='\033[1;33m'
C_PURPLE='\033[0;35m'
C_NC='\033[0m' # No Color
BOLD='\033[1m'

clear

# --- Modern ASCII Art ---
echo -e "${C_CYAN}${BOLD}"
echo "  ____  ______ ______ _   _ __     __"
echo " |  _ \|  ____|  ____| \ | |\ \   / /"
echo " | |_) | |__  | |__  |  \| | \ \_/ / "
echo " |  _ <|  __| |  __| | . \` |  \   /  "
echo " | |_) | |____| |____| |\  |   | |   "
echo " |____/|______|______|_| \_|   |_|   "
echo -e "${C_NC}"
echo -e "${C_PURPLE}${BOLD}✦✦✦ BEENY NODE AGENT AUTO-INSTALLER ✦✦✦${C_NC}\n"

# --- Root Check ---
if [ "$EUID" -ne 0 ]; then
    echo -e "${C_RED}❌ Error: Please run this script as root!${C_NC}"
    exit 1
fi

echo -e "${C_BLUE}[⚙] Starting Installation Process...${C_NC}\n"

# --- Step 1 ---
echo -ne "${C_YELLOW}➜ [1/5] Installing Dependencies (OpenVPN, Python)... ${C_NC}"
apt-get update -y > /dev/null 2>&1
apt-get install -y openvpn python3 python3-pip iptables iptables-persistent net-tools curl > /dev/null 2>&1
pip3 install flask requests --break-system-packages > /dev/null 2>&1 || pip3 install flask requests > /dev/null 2>&1
echo -e "${C_GREEN}✔ Done${C_NC}"

# --- Step 2 ---
echo -ne "${C_YELLOW}➜ [2/5] Configuring Network Routing (NAT)... ${C_NC}"
echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-beeny-vpn.conf
sysctl -p /etc/sysctl.d/99-beeny-vpn.conf > /dev/null 2>&1
INTERFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
iptables -t nat -A POSTROUTING -o $INTERFACE -j MASQUERADE
iptables-save > /etc/iptables/rules.v4
netfilter-persistent save > /dev/null 2>&1
echo -e "${C_GREEN}✔ Done${C_NC}"

# --- Step 3 ---
echo -ne "${C_YELLOW}➜ [3/5] Setting up Directories & API Key... ${C_NC}"
mkdir -p /opt/beeny-agent
mkdir -p /etc/openvpn/server
mkdir -p /etc/openvpn/users
API_KEY=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)

cat << EOF > /opt/beeny-agent/config.py
AGENT_API_KEY = "$API_KEY"
EOF
echo -e "${C_GREEN}✔ Done${C_NC}"

# --- Step 4 ---
echo -ne "${C_YELLOW}➜ [4/5] Writing Agent Script... ${C_NC}"
cat << 'EOF' > /opt/beeny-agent/agent.py
from flask import Flask, request, jsonify
from config import AGENT_API_KEY
import subprocess
import os

app = Flask(__name__)

def verify_api_key():
    auth = request.headers.get("Authorization", "")
    if not auth.startswith("Bearer "):
        return False
    token = auth.replace("Bearer ", "")
    return token == AGENT_API_KEY

@app.route("/api/node/stats")
def stats():
    if not verify_api_key():
        return jsonify({"error": "Unauthorized"}), 401
    return jsonify({"status": "online"})

@app.route("/api/node/bootstrap-openvpn", methods=["POST"])
def bootstrap_openvpn():
    if not verify_api_key():
        return jsonify({"error": "Unauthorized"}), 401

    data = request.get_json()
    ca_crt = data.get("ca_crt")
    ta_key = data.get("ta_key")
    server_crt = data.get("server_crt")
    server_key = data.get("server_key")
    server_conf = data.get("server_conf")

    try:
        if ca_crt:
            with open("/etc/openvpn/ca.crt", "w") as f: f.write(ca_crt)
        if ta_key:
            with open("/etc/openvpn/ta.key", "w") as f: f.write(ta_key)
        if server_crt:
            with open("/etc/openvpn/server/server.crt", "w") as f: f.write(server_crt)
        if server_key:
            with open("/etc/openvpn/server/server.key", "w") as f: f.write(server_key)
        if server_conf:
            with open("/etc/openvpn/server/server.conf", "w") as f: f.write(server_conf)
            
        subprocess.run(["systemctl", "restart", "openvpn-server@server"], check=False)
        return jsonify({"success": True, "message": "Bootstrap completed & OpenVPN started"})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@app.route("/api/node/install-cert", methods=["POST"])
def install_cert():
    if not verify_api_key():
        return jsonify({"error": "Unauthorized"}), 401

    data = request.get_json()
    username = data.get("username")
    cert = data.get("cert")
    key = data.get("key")

    if not username or "/" in username or ".." in username:
        return jsonify({"error": "invalid username"}), 400

    try:
        with open(f"/etc/openvpn/users/{username}.crt", "w") as f: f.write(cert)
        with open(f"/etc/openvpn/users/{username}.key", "w") as f: f.write(key)
        return jsonify({"success": True, "message": f"Certificate installed for {username}"})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001)
EOF
echo -e "${C_GREEN}✔ Done${C_NC}"

# --- Step 5 ---
echo -ne "${C_YELLOW}➜ [5/5] Creating & Starting Systemd Service... ${C_NC}"
cat << EOF > /etc/systemd/system/beeny-agent.service
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

# --- Summary Box ---
SERVER_IP=$(curl -s https://api.ipify.org)

echo -e "\n${C_GREEN}${BOLD}🎉 Installation Completed Successfully!${C_NC}"
echo -e "${C_CYAN}╭────────────────────────────────────────────────────────╮${C_NC}"
echo -e "${C_CYAN}│${C_NC}  ${C_PURPLE}Add this Node to your Beeny Central Panel:${C_NC}            ${C_CYAN}│${C_NC}"
echo -e "${C_CYAN}│${C_NC}                                                        ${C_CYAN}│${C_NC}"
echo -e "${C_CYAN}│${C_NC}  ${BOLD}IP Address :${C_NC} ${C_YELLOW}$SERVER_IP${C_NC}                             ${C_CYAN}│${C_NC}"
echo -e "${C_CYAN}│${C_NC}  ${BOLD}API Key    :${C_NC} ${C_GREEN}$API_KEY${C_NC} ${C_CYAN}│${C_NC}"
echo -e "${C_CYAN}│${C_NC}  ${BOLD}Port       :${C_NC} 5001                                     ${C_CYAN}│${C_NC}"
echo -e "${C_CYAN}╰────────────────────────────────────────────────────────╯${C_NC}\n"
