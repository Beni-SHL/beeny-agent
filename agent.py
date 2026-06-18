from flask import Flask, request, jsonify
from config import AGENT_API_KEY, AGENT_PORT
import subprocess
import os
import logging

# تنظیم لاگ برای دیدن خطاها
logging.basicConfig(filename='/opt/beeny-agent/agent.log', level=logging.INFO,
                    format='%(asctime)s %(levelname)s: %(message)s')

app = Flask(__name__)

def verify_api_key():
    auth = request.headers.get("Authorization", "")
    if not auth.startswith("Bearer "): 
        return False
    return auth.replace("Bearer ", "") == AGENT_API_KEY

def find_systemctl():
    """پیدا کردن مسیر کامل systemctl"""
    for path in ["/usr/bin/systemctl", "/bin/systemctl", "/usr/sbin/systemctl"]:
        if os.path.exists(path):
            return path
    return "systemctl"  # fallback

def run_systemctl(command_args):
    """اجرای دستور systemctl با لاگ"""
    cmd = [find_systemctl()] + command_args
    logging.info(f"Running: {' '.join(cmd)}")
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=False)
        if result.returncode != 0:
            logging.error(f"Command failed: {result.stderr.strip()}")
        else:
            logging.info(f"Command OK: {result.stdout.strip()}")
        return result
    except Exception as e:
        logging.error(f"Exception running {cmd}: {str(e)}")
        raise

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
    try:
        os.makedirs("/etc/openvpn/server", exist_ok=True)
        os.makedirs("/etc/openvpn/ccd", exist_ok=True)

        # نوشتن فایل‌های ارسالی
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

        # reload systemd و فعال‌سازی سرویس OpenVPN
        run_systemctl(["daemon-reload"])
        run_systemctl(["enable", "openvpn-server@server"])
        run_systemctl(["restart", "openvpn-server@server"])

        logging.info("Bootstrap completed successfully.")
        return jsonify({"success": True, "message": "Bootstrap completed & OpenVPN started"})

    except Exception as e:
        logging.error(f"Bootstrap error: {str(e)}")
        return jsonify({"success": False, "error": str(e)}), 500

@app.route("/api/node/install-cert", methods=["POST"])
def install_cert():
    if not verify_api_key():
        return jsonify({"error": "Unauthorized"}), 401

    data = request.get_json()
    username = data.get("username")
    if not username or "/" in username or ".." in username:
        return jsonify({"error": "invalid"}), 400
    try:
        os.makedirs("/etc/openvpn/users", exist_ok=True)
        with open(f"/etc/openvpn/users/{username}.crt", "w") as f:
            f.write(data.get("cert"))
        with open(f"/etc/openvpn/users/{username}.key", "w") as f:
            f.write(data.get("key"))
        return jsonify({"success": True})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=AGENT_PORT)
