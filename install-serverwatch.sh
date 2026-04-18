#!/usr/bin/env bash

set -e

echo "=============================="
echo "   ServerWatch Installer"
echo "=============================="
echo

# ===== INPUT =====

read -p "Enter Discord Webhook URL: " WEBHOOK
read -p "Enter Server ID (e.g. SG-1): " SERVER_ID

echo
echo "[+] Installing dependencies..."
sudo apt update -y
sudo apt install -y python3 python3-psutil python3-requests

echo "[+] Creating directory..."
sudo mkdir -p /opt/serverwatch

echo "[+] Writing script..."

sudo tee /opt/serverwatch/serverwatch.py > /dev/null <<'EOF'
#!/usr/bin/env python3

import time
import psutil
import requests
import subprocess
import re
import ipaddress
from datetime import datetime

# =========================
# CONFIG
# =========================

SERVER_ID = "__SERVER_ID__"
WEBHOOK = "__WEBHOOK__"

# ===== PROCESS WATCH =====
THRESHOLD_CPU = 80
THRESHOLD_MEM = 50
DURATION = 60
CHECK_INTERVAL = 5
AUTO_EXPIRE = 300

IGNORE_PROCESS_USERS = set()  # future use
IGNORE_PROCESS_NAMES = {"systemd", "kworker", "ksoftirqd", "rcu_sched"}
IGNORE_CMD_KEYWORDS = {"prometheus", "grafana", "netdata"}

# ===== LOGIN WATCH =====
IGNORE_LOGIN_USERS = {"coolifyuser"}

WHITELIST_IPS = {
    "127.0.0.1",
    "10.0.1.12",
}

WHITELIST_SUBNETS = {}

IGNORE_LOCALHOST = True

# =========================
# STATE
# =========================

tracked = {}
alerted = set()

last_cursor = None
SSH_UNIT = "ssh"

# =========================
# COMMON
# =========================

def send_webhook(title, fields, color=16711680):
    data = {
        "username": "ServerWatch",
        "embeds": [{
            "title": f"{title} ({SERVER_ID})",
            "color": color,
            "fields": fields,
            "timestamp": datetime.utcnow().isoformat(),
            "footer": {
                "text": f"{SERVER_ID} • {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
            }
        }]
    }

    try:
        requests.post(WEBHOOK, json=data, timeout=5)
    except Exception as e:
        print("Webhook failed:", e)

def clean_log(raw):
    if not raw:
        return "N/A"

    # Remove triple backticks (breaks Discord formatting)
    raw = raw.replace("```", "`")

    # Trim length (Discord field limit ~1024 chars)
    if len(raw) > 900:
        raw = raw[:900] + "..."

    return raw

# =========================
# PROCESS WATCH
# =========================

def get_cmd(p):
    try:
        cmd = " ".join(p.cmdline())
        return cmd[:1000] if cmd else p.name()
    except:
        return p.name()

def should_ignore_process(p, cmd):
    try:
        if p.username() in IGNORE_PROCESS_USERS:
            return True

        if p.name() in IGNORE_PROCESS_NAMES:
            return True

        for k in IGNORE_CMD_KEYWORDS:
            if k in cmd.lower():
                return True

    except:
        return True

    return False

def alert_process_high(p, cpu, mem):
    try:
        parent = psutil.Process(p.ppid())
        parent_cmd = get_cmd(parent)
    except:
        parent_cmd = "N/A"

    fields = [
        {"name": "PID", "value": str(p.pid), "inline": True},
        {"name": "PPID", "value": str(p.ppid()), "inline": True},
        {"name": "User", "value": str(p.username()), "inline": True},
        {"name": "CPU %", "value": f"{cpu:.2f}", "inline": True},
        {"name": "Memory %", "value": f"{mem:.2f}", "inline": True},
        {"name": "Command", "value": get_cmd(p), "inline": False},
        {"name": "Parent CMD", "value": parent_cmd, "inline": False},
    ]

    send_webhook("⚠️ High Resource Process", fields)

def alert_process_exit(info):
    fields = [
        {"name": "PID", "value": str(info["pid"]), "inline": True},
        {"name": "User", "value": info["user"], "inline": True},
        {"name": "Runtime (s)", "value": str(info["runtime"]), "inline": True},
        {"name": "Command", "value": info["cmd"], "inline": False},
    ]

    send_webhook("ℹ️ Process Ended", fields, color=3447003)

def process_loop():
    global tracked, alerted

    for p in psutil.process_iter():
        try:
            p.cpu_percent()
        except:
            pass

    while True:
        now = time.time()
        seen = set()

        for p in psutil.process_iter(['pid', 'ppid', 'username']):
            try:
                key = (p.pid, p.create_time())
                seen.add(key)

                cpu = p.cpu_percent()
                mem = p.memory_percent()
                cmd = get_cmd(p)

                if should_ignore_process(p, cmd):
                    continue

                if key not in tracked:
                    tracked[key] = {
                        "time": 0,
                        "first_seen": now,
                        "pid": p.pid,
                        "user": p.username(),
                        "cmd": cmd
                    }

                if cpu > THRESHOLD_CPU or mem > THRESHOLD_MEM:
                    tracked[key]["time"] += CHECK_INTERVAL

                    if tracked[key]["time"] >= DURATION and key not in alerted:
                        alert_process_high(p, cpu, mem)
                        alerted.add(key)
                else:
                    tracked[key]["time"] = 0
                    alerted.discard(key)

            except (psutil.NoSuchProcess, psutil.AccessDenied):
                continue

        # cleanup
        for key in list(tracked.keys()):
            info = tracked[key]

            if key not in seen:
                if key in alerted:
                    runtime = int(now - info["first_seen"])
                    alert_process_exit({
                        "pid": info["pid"],
                        "user": info["user"],
                        "cmd": info["cmd"],
                        "runtime": runtime
                    })

                tracked.pop(key, None)
                alerted.discard(key)
                continue

            if now - info["first_seen"] > AUTO_EXPIRE:
                tracked.pop(key, None)
                alerted.discard(key)

        time.sleep(CHECK_INTERVAL)

# =========================
# LOGIN WATCH
# =========================

def detect_ssh_unit():
    global SSH_UNIT
    try:
        out = subprocess.check_output(
            ["systemctl", "list-units", "--type=service", "--all"],
            text=True
        )
        if "sshd.service" in out:
            SSH_UNIT = "sshd"
    except:
        pass

def is_ip_whitelisted(ip):
    try:
        ip_obj = ipaddress.ip_address(ip)

        if ip in WHITELIST_IPS:
            return True

        for subnet in WHITELIST_SUBNETS:
            if ip_obj in ipaddress.ip_network(subnet, strict=False):
                return True
    except:
        return False

    return False

def alert_login(user, ip, method, raw):
    fields = [
        {"name": "User", "value": user, "inline": True},
        {"name": "IP", "value": ip, "inline": True},
        {"name": "Method", "value": method, "inline": True},
        {"name": "Log", "value": clean_log(raw), "inline": False},
    ]

    send_webhook("🔐 SSH Login", fields, color=3066993)

def init_cursor():
    global last_cursor
    try:
        out = subprocess.check_output(
            ["journalctl", "-u", SSH_UNIT, "-n", "1", "--show-cursor", "--no-pager"],
            text=True
        )
        for line in out.splitlines():
            if line.startswith("-- cursor:"):
                last_cursor = line.split(":", 1)[1].strip()
    except:
        pass

def login_loop():
    global last_cursor

    while True:
        try:
            cmd = [
                "journalctl",
                "-u", SSH_UNIT,
                "-n", "50",
                "--no-pager",
                "--show-cursor"
            ]

            if last_cursor:
                cmd += ["--after-cursor", last_cursor]

            out = subprocess.check_output(cmd, text=True)

            new_cursor = None

            for line in out.splitlines():
                if line.startswith("-- cursor:"):
                    new_cursor = line.split(":", 1)[1].strip()
                    continue

                if "Accepted password" in line or "Accepted publickey" in line:
                    m = re.search(r"Accepted (\w+) for (\S+) from ([\d\.]+)", line)
                    if not m:
                        continue

                    method, user, ip = m.groups()

                    if IGNORE_LOCALHOST and ip == "127.0.0.1":
                        continue

                    if user in IGNORE_LOGIN_USERS:
                        continue

                    if is_ip_whitelisted(ip):
                        continue

                    alert_login(user, ip, method, line.strip())

            if new_cursor:
                last_cursor = new_cursor

        except Exception as e:
            print("Login error:", e)

        time.sleep(CHECK_INTERVAL)

# =========================
# MAIN
# =========================

if __name__ == "__main__":
    print("ServerWatch started...")

    detect_ssh_unit()
    init_cursor()

    import threading

    t1 = threading.Thread(target=process_loop, daemon=True)
    t2 = threading.Thread(target=login_loop, daemon=True)

    t1.start()
    t2.start()

    while True:
        time.sleep(60)
EOF

sudo sed -i "s|__SERVER_ID__|$SERVER_ID|g" /opt/serverwatch/serverwatch.py
sudo sed -i "s|__WEBHOOK__|$WEBHOOK|g" /opt/serverwatch/serverwatch.py

echo "[+] Setting permissions..."
sudo chmod +x /opt/serverwatch/serverwatch.py

echo "[+] Creating systemd service..."

sudo tee /etc/systemd/system/serverwatch.service > /dev/null <<EOF
[Unit]
Description=Server Watch
After=network.target

[Service]
ExecStart=/usr/bin/python3 /opt/serverwatch/serverwatch.py
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

echo "[+] Starting service..."
sudo systemctl daemon-reload
sudo systemctl enable serverwatch
sudo systemctl restart serverwatch

echo
echo "✅ Installation complete!"
echo "Check status with: systemctl status serverwatch"
