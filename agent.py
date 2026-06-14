from flask import Flask, request, jsonify
from config import AGENT_API_KEY
import subprocess

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


@app.route("/api/node/create-user", methods=["POST"])
def create_user():

    if not verify_api_key():
        return jsonify({"error": "Unauthorized"}), 401

    data = request.get_json()

    username = data.get("username")
    password = data.get("password")
    expire_date = data.get("expire_date")
    max_devices = data.get("max_devices")

    try:

        result = subprocess.run(
            ["/opt/beeny-panel/scripts/create_vpn_user.sh", username],
            capture_output=True,
            text=True,
            check=True
        )

        return jsonify({
            "success": True,
            "config": result.stdout.strip()
        })

    except Exception as e:

        return jsonify({
            "success": False,
            "error": str(e)
        }), 500
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001)
