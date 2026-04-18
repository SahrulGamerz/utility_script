#!/usr/bin/env bash

set -e

echo "=============================="
echo "   ServerWatch Removal Tool"
echo "=============================="
echo

# ===== STOP & DISABLE SERVICE =====
echo "[+] Stopping service..."
sudo systemctl stop serverwatch 2>/dev/null || true

echo "[+] Disabling service..."
sudo systemctl disable serverwatch 2>/dev/null || true

# ===== REMOVE SYSTEMD FILE =====
echo "[+] Removing systemd service..."
sudo rm -f /etc/systemd/system/serverwatch.service

# ===== RELOAD SYSTEMD =====
echo "[+] Reloading systemd..."
sudo systemctl daemon-reload
sudo systemctl reset-failed

# ===== REMOVE FILES =====
echo "[+] Removing /opt/serverwatch..."
sudo rm -rf /opt/serverwatch

# ===== OPTIONAL: REMOVE OLD PROCWATCH =====
echo
read -p "Remove old ProcWatch (if exists)? (y/N): " REMOVE_OLD

if [[ "$REMOVE_OLD" =~ ^[Yy]$ ]]; then
    echo "[+] Removing old procwatch service..."
    sudo systemctl stop procwatch 2>/dev/null || true
    sudo systemctl disable procwatch 2>/dev/null || true
    sudo rm -f /etc/systemd/system/procwatch.service

    echo "[+] Removing /opt/procwatch..."
    sudo rm -rf /opt/procwatch

    echo "[+] Reloading systemd again..."
    sudo systemctl daemon-reload
    sudo systemctl reset-failed
fi

# ===== OPTIONAL: REMOVE USER =====
echo
read -p "Remove procwatch user (if exists)? (y/N): " REMOVE_USER

if [[ "$REMOVE_USER" =~ ^[Yy]$ ]]; then
    if id "procwatch" &>/dev/null; then
        echo "[+] Deleting user procwatch..."
        sudo userdel -r procwatch 2>/dev/null || true
    else
        echo "[i] procwatch user not found"
    fi
fi

echo
echo "✅ Removal complete!"
echo
echo "You can verify with:"
echo "  systemctl status serverwatch"
echo "  ls /opt/serverwatch"
