import os # اگر اون بالا ایمپورت نشده، اضافه‌اش کن

@app.route("/api/node/status-log", methods=["GET"])
def get_status_log():
    if not verify_api_key(): return jsonify({"error": "Unauthorized"}), 401
    try:
        # فرستادن لاگ مصرفی نود برای سرور مرکزی
        if os.path.exists("/var/log/openvpn-status.log"):
            with open("/var/log/openvpn-status.log", "r") as f:
                return jsonify({"success": True, "log": f.read()})
        return jsonify({"success": True, "log": ""})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@app.route("/api/node/kill-user", methods=["POST"])
def kill_user():
    if not verify_api_key(): return jsonify({"error": "Unauthorized"}), 401
    data = request.get_json()
    username = data.get("username")
    if not username: return jsonify({"error": "invalid"}), 400
    try:
        # ۱. مسدودسازی دائمی کاربر روی این نود
        os.makedirs("/etc/openvpn/ccd", exist_ok=True)
        with open(f"/etc/openvpn/ccd/{username}", "w") as f:
            f.write("disable\n")
        
        # ۲. شوت کردنِ آنی کاربر از تونل (از طریق پورت مدیریت اوپن‌وی‌پی‌ان)
        os.system(f"printf 'kill {username}\\n' | nc 127.0.0.1 7505 -w 1 >/dev/null 2>&1")
        return jsonify({"success": True})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500
