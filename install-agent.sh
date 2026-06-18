#!/bin/bash

# ─── رنگ‌های اصلی ─────────────────────────────────
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_CYAN='\033[0;36m'
C_YELLOW='\033[1;33m'
C_PURPLE='\033[0;35m'
C_NC='\033[0m'
BOLD='\033[1m'
BLINK='\033[5m'

# ─── پاستیل‌های رنگین‌کمان برای BEENY ─────────────
PASTEL_PINK='\033[38;2;255;179;186m'
PASTEL_PEACH='\033[38;2;255;223;186m'
PASTEL_YELLOW='\033[38;2;255;255;186m'
PASTEL_MINT='\033[38;2;186;255;201m'
PASTEL_LAVENDER='\033[38;2;186;225;255m'

# ─── توابع انیمیشنی ──────────────────────────────
spinner() {
    local pid=$1
    local delay=0.08
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    while kill -0 $pid 2>/dev/null; do
        for ((i=0; i<${#spin}; i++)); do
            printf "\r   ${C_CYAN}%s${C_NC}  Processing..." "${spin:$i:1}"
            sleep $delay
        done
    done
    printf "\r   ${C_GREEN}✓${C_NC} Done           \n"
}

progress_bar() {
    local cur=$1
    local total=$2
    local pct=$((100 * cur / total))
    local fill=$((pct / 2))
    local empty=$((50 - fill))
    printf "\r["
    for ((i=0; i<fill; i++)); do printf "█"; done
    for ((i=0; i<empty; i++)); do printf "░"; done
    printf "] %3d%%" "$pct"
}

typewriter() {
    local text="$1"
    local delay=0.02
    for ((i=0; i<${#text}; i++)); do
        printf "%s" "${text:$i:1}"
        sleep $delay
    done
    echo
}

# ─── پاکسازی و بنر ────────────────────────────────
clear
echo -e "${C_CYAN}${BOLD}"
typewriter "  ____  ______ ______ _   _ __     __"
typewriter " |  _ \|  ____|  ____| \ | |\ \   / /"
typewriter " | |_) | |__  | |__  |  \| | \ \_/ / "
typewriter " |  _ <|  __| |  __| | . \` |  \   /  "
typewriter " | |_) | |____| |____| |\  |   | |   "
typewriter " |____/|______|______|_| \_|   |_|   ${C_NC}"

# خط ویژه با BEENY رنگین‌کمانی
echo -e -n "${C_PURPLE}${BOLD}${BLINK}✦✦✦ ${C_NC}"
echo -e -n "${PASTEL_PINK}B${PASTEL_PEACH}E${PASTEL_YELLOW}E${PASTEL_MINT}N${PASTEL_LAVENDER}Y"
echo -e "${C_PURPLE}${BOLD}${BLINK} NODE AGENT AUTO-INSTALLER ✦✦✦${C_NC}\n"
sleep 1

# ─── بررسی روت ────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    echo -e "${C_RED}❌ Error: Please run as root!${C_NC}"
    exit 1
fi

# ─── پرسش از کاربر ────────────────────────────────
echo -e "${C_CYAN}╭────────────────────────────────────────────────────────╮${C_NC}"
echo -e "${C_CYAN}│${C_NC} ${BOLD}Node Configuration Setup${C_NC}                               ${C_CYAN}│${C_NC}"
echo -e "${C_CYAN}╰────────────────────────────────────────────────────────╯${C_NC}"

read -p "🌐 Enter Domain (Leave empty to use Auto IP): " USER_DOMAIN
read -p "🔌 Enter Agent Port (Press Enter for default 5001): " USER_PORT

USER_PORT=${USER_PORT:-5001}

if [ -z "$USER_DOMAIN" ]; then
    SERVER_IP=$(curl -s https://api.ipify.org || echo "YOUR_SERVER_IP")
    NODE_ADDRESS=$SERVER_IP
else
    NODE_ADDRESS=$USER_DOMAIN
fi

# ─── تولید کلید API همینجا (نه داخل subshell) ─────
API_KEY=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)

echo -e "\n${C_GREEN}✔ Configuration Saved. Starting Installation...${C_NC}\n"
sleep 1

# ─── مراحل نصب (۶ مرحله) ─────────────────────────
TOTAL_STEPS=6
STEP=0

# مرحله ۱
((STEP++))
echo -e "${BOLD}${C_CYAN}➜ [${STEP}/${TOTAL_STEPS}]${C_NC} Installing Dependencies (OpenVPN, Python)..."
progress_bar $STEP $TOTAL_STEPS
echo ""   # برای تمیز شدن خط بعدی
(
    export DEBIAN_FRONTEND=noninteractive
    apt-get remove -y needrestart > /dev/null 2>&1 || true
    apt-get update -y > /dev/null 2>&1
    mkdir -p /etc/openvpn/server /etc/openvpn/ccd /etc/openvpn/users
    touch /etc/openvpn/server/server.conf
    echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections 2>/dev/null || true
    echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections 2>/dev/null || true
    apt-get install -y -q -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
        openvpn python3 python3-pip iptables iptables-persistent net-tools curl > /dev/null 2>&1
    pip3 install flask requests --break-system-packages > /dev/null 2>&1 || \
        pip3 install flask requests > /dev/null 2>&1
) &
spinner $!

# مرحله ۲
((STEP++))
echo -e "${BOLD}${C_CYAN}➜ [${STEP}/${TOTAL_STEPS}]${C_NC} Configuring Network Routing & Firewall..."
progress_bar $STEP $TOTAL_STEPS
echo ""
(
    echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-beeny-vpn.conf
    sysctl -p /etc/sysctl.d/99-beeny-vpn.conf > /dev/null 2>&1
    INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n 1)
    if [ -n "$INTERFACE" ]; then
        iptables -t nat -F POSTROUTING || true
        iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o "$INTERFACE" -j MASQUERADE || true
        iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT || true
        iptables -I FORWARD -s 10.8.0.0/24 -j ACCEPT || true
    fi
    iptables -I INPUT -p tcp --dport "$USER_PORT" -j ACCEPT || true
    iptables-save > /etc/iptables/rules.v4 || true
    netfilter-persistent save > /dev/null 2>&1 || true
) &
spinner $!

# مرحله ۳
((STEP++))
echo -e "${BOLD}${C_CYAN}➜ [${STEP}/${TOTAL_STEPS}]${C_NC} Setting up Directories & Config..."
progress_bar $STEP $TOTAL_STEPS
echo ""
(
    mkdir -p /opt/beeny-agent
    cat << EOF > /opt/beeny-agent/config.py
AGENT_API_KEY = "$API_KEY"
AGENT_PORT = $USER_PORT
AGENT_HOST = "$NODE_ADDRESS"
EOF
) &
spinner $!

# مرحله ۴
((STEP++))
echo -e "${BOLD}${C_CYAN}➜ [${STEP}/${TOTAL_STEPS}]${C_NC} Writing Agent Script..."
progress_bar $STEP $TOTAL_STEPS
echo ""
(
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
        os.makedirs("/etc/openvpn/server", exist_ok=True)
        os.makedirs("/etc/openvpn/ccd", exist_ok=True)
        
        if data.get("ca_crt"):
            with open("/etc/openvpn/ca.crt", "w") as f: f.write(data.get("ca_crt"))
        if data.get("ta_key"):
            with open("/etc/openvpn/ta.key", "w") as f: f.write(data.get("ta_key"))
        if data.get("server_crt"):
            with open("/etc/openvpn/server/server.crt", "w") as f: f.write(data.get("server_crt"))
        if data.get("server_key"):
            with open("/etc/openvpn/server/server.key", "w") as f: f.write(data.get("server_key"))
        if data.get("dh_pem"):
            with open("/etc/openvpn/dh.pem", "w") as f: f.write(data.get("dh_pem"))
        if data.get("crl_pem"):
            with open("/etc/openvpn/crl.pem", "w") as f: f.write(data.get("crl_pem"))
        if data.get("server_conf"):
            with open("/etc/openvpn/server/server.conf", "w") as f: f.write(data.get("server_conf"))
        
        subprocess.run(["systemctl", "daemon-reload"], check=False)
        subprocess.run(["systemctl", "enable", "openvpn@server"], check=False)
        subprocess.run(["systemctl", "restart", "openvpn@server"], check=False)
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
        os.makedirs("/etc/openvpn/users", exist_ok=True)
        with open(f"/etc/openvpn/users/{username}.crt", "w") as f: f.write(data.get("cert"))
        with open(f"/etc/openvpn/users/{username}.key", "w") as f: f.write(data.get("key"))
        return jsonify({"success": True})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=AGENT_PORT)
EOF
) &
spinner $!

# مرحله ۵
((STEP++))
echo -e "${BOLD}${C_CYAN}➜ [${STEP}/${TOTAL_STEPS}]${C_NC} Starting Systemd Service..."
progress_bar $STEP $TOTAL_STEPS
echo ""
(
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
) &
spinner $!

# مرحله ۶
((STEP++))
echo -e "${BOLD}${C_CYAN}➜ [${STEP}/${TOTAL_STEPS}]${C_NC} Creating Node Manager Menu..."
progress_bar $STEP $TOTAL_STEPS
echo ""
(
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
        iptables -I INPUT -p tcp --dport "$newp" -j ACCEPT || true
        netfilter-persistent save > /dev/null 2>&1 || true
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
) &
spinner $!

# ─── پایان نصب ──────────────────────────────────
echo -e "\n${C_GREEN}${BOLD}🎉 Installation Completed Successfully!${C_NC}"
echo -e "${C_CYAN}╭────────────────────────────────────────────────────────╮${C_NC}"
echo -e "${C_CYAN}│${C_NC}  ${C_PURPLE}Add this Node to your Beeny Central Panel:${C_NC}            ${C_CYAN}│${C_NC}"
echo -e "${C_CYAN}│${C_NC}  ${BOLD}Address    :${C_NC} ${C_YELLOW}$NODE_ADDRESS${C_NC}                             ${C_CYAN}│${C_NC}"
echo -e "${C_CYAN}│${C_NC}  ${BOLD}Port       :${C_NC} $USER_PORT                                     ${C_CYAN}│${C_NC}"
echo -e "${C_CYAN}│${C_NC}  ${BOLD}API Key    :${C_NC} ${C_GREEN}$API_KEY${C_NC} ${C_CYAN}│${C_NC}"
echo -e "${C_CYAN}╰────────────────────────────────────────────────────────╯${C_NC}"
echo -e "${C_YELLOW}💡 Tip: Type ${BOLD}'beeny'${C_NC}${C_YELLOW} anytime in this terminal to open the manager menu.${C_NC}\n"
