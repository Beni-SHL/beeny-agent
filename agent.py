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

    return jsonify({
        "status": "online"
    })

@app.route("/api/node/bootstrap", methods=["POST"])
def bootstrap():

    if not verify_api_key():
        return jsonify({"error": "Unauthorized"}), 401

    data = request.get_json()

    ca_crt = data.get("ca_crt")
    ta_key = data.get("ta_key")

    try:

        import os

        os.makedirs("/etc/openvpn", exist_ok=True)

        with open("/etc/openvpn/ca.crt", "w") as f:
            f.write(ca_crt)

        with open("/etc/openvpn/ta.key", "w") as f:
            f.write(ta_key)

        return jsonify({
            "success": True,
            "message": "Bootstrap completed"
        })

    except Exception as e:

        return jsonify({
            "success": False,
            "error": str(e)
        }), 500

@app.route("/api/node/install-cert", methods=["POST"])
def install_cert():

    if not verify_api_key():
        return jsonify({"error": "Unauthorized"}), 401

    data = request.get_json()

    username = data.get("username")
    cert = data.get("cert")
    key = data.get("key")

    if not username:
        return jsonify({"error": "username required"}), 400

    if "/" in username or ".." in username:
        return jsonify({"error": "invalid username"}), 400

    if not cert or not key:
        return jsonify({"error": "cert/key required"}), 400

    try:

        os.makedirs("/etc/openvpn/users", exist_ok=True)

        with open(f"/etc/openvpn/users/{username}.crt", "w") as f:
            f.write(cert)

        with open(f"/etc/openvpn/users/{username}.key", "w") as f:
            f.write(key)

        return jsonify({
            "success": True,
            "message": f"Certificate installed for {username}"
        })

    except Exception as e:

        return jsonify({
            "success": False,
            "error": str(e)
        }), 500

@app.route("/api/node/crl-update", methods=["POST"])
def crl_update():

    if not verify_api_key():
        return jsonify({"error": "Unauthorized"}), 401

    data = request.get_json()

    crl = data.get("crl")

    if not crl:
        return jsonify({"error": "crl required"}), 400

    try:

        with open("/etc/openvpn/crl.pem", "w") as f:
            f.write(crl)

        return jsonify({
            "success": True,
            "message": "CRL updated"
        })

    except Exception as e:

        return jsonify({
            "success": False,
            "error": str(e)
        }), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001)
