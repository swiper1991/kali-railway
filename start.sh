#!/bin/bash
set -Eeuo pipefail

RDP_USER="${RDP_USER:-kali}"
RDP_PASSWORD="${RDP_PASSWORD:?RDP_PASSWORD belum diatur}"

echo "[INIT] Preparing Kali Linux..."

# Create RDP user
if ! id "$RDP_USER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$RDP_USER"
fi

echo "$RDP_USER:$RDP_PASSWORD" | chpasswd
usermod -aG sudo "$RDP_USER"

HOME_DIR="/home/$RDP_USER"

mkdir -p "$HOME_DIR"
mkdir -p /var/run/dbus
mkdir -p /var/run/xrdp
mkdir -p /var/log/xrdp

chown -R "$RDP_USER:$RDP_USER" "$HOME_DIR"

# DBus system daemon
if ! pgrep -x dbus-daemon >/dev/null 2>&1; then
    dbus-daemon --system --fork
fi

# Xauthority
touch "$HOME_DIR/.Xauthority"
chown "$RDP_USER:$RDP_USER" "$HOME_DIR/.Xauthority"
chmod 600 "$HOME_DIR/.Xauthority"

# XFCE session
cat > "$HOME_DIR/.xsession" <<'EOF'
#!/bin/bash

unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR

exec dbus-run-session -- startxfce4
EOF

chmod +x "$HOME_DIR/.xsession"
chown "$RDP_USER:$RDP_USER" "$HOME_DIR/.xsession"

# XRDP startup configuration
cat > /etc/xrdp/startwm.sh <<'EOF'
#!/bin/sh

unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR

exec dbus-run-session -- startxfce4
EOF

chmod +x /etc/xrdp/startwm.sh

# Fix permissions
chown -R "$RDP_USER:$RDP_USER" "$HOME_DIR"

echo "[CHECK] Installed binaries:"
command -v dbus-daemon
command -v dbus-run-session
command -v xrdp
command -v xrdp-sesman
command -v Xorg

echo "[START] Starting XRDP Session Manager..."

xrdp-sesman --nodaemon \
    >> /var/log/xrdp-sesman.log 2>&1 &

SESMAN_PID=$!

sleep 2

if ! kill -0 "$SESMAN_PID" 2>/dev/null; then
    echo "[ERROR] XRDP Session Manager failed"
    cat /var/log/xrdp-sesman.log
    exit 1
fi

echo "[START] Starting XRDP Server..."

xrdp --nodaemon \
    >> /var/log/xrdp.log 2>&1 &

XRDP_PID=$!

# Forward logs to Railway
tail -F /var/log/xrdp.log /var/log/xrdp-sesman.log &
TAIL_PID=$!

cleanup() {
    kill "$TAIL_PID" "$XRDP_PID" "$SESMAN_PID" 2>/dev/null || true
}

trap cleanup EXIT

echo "[READY] Kali Linux RDP is running on port 3389"

wait "$XRDP_PID"
