#!/bin/bash
set -Eeuo pipefail

RDP_USER="${RDP_USER:-kali}"
RDP_PASSWORD="${RDP_PASSWORD:?RDP_PASSWORD belum diatur}"

echo "[INIT] Preparing Kali Linux..."

# Create user
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

# Start DBus
dbus-daemon --system --fork || true

# Generate dedicated XRDP SSL certificate
echo "[INIT] Generating XRDP certificate..."

openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout /etc/xrdp/railway.key \
    -out /etc/xrdp/railway.crt \
    -days 3650 \
    -subj "/CN=railway-kali"

chown xrdp:xrdp /etc/xrdp/railway.key
chown xrdp:xrdp /etc/xrdp/railway.crt

chmod 600 /etc/xrdp/railway.key
chmod 644 /etc/xrdp/railway.crt

# Configure XRDP certificate
sed -i \
    -e 's|^certificate=.*|certificate=/etc/xrdp/railway.crt|' \
    -e 's|^key_file=.*|key_file=/etc/xrdp/railway.key|' \
    /etc/xrdp/xrdp.ini

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

# XRDP window manager
cat > /etc/xrdp/startwm.sh <<'EOF'
#!/bin/sh
exec /etc/X11/Xsession
EOF

chmod +x /etc/xrdp/startwm.sh

echo "[CHECK] dbus: $(command -v dbus-daemon)"
echo "[CHECK] xrdp: $(command -v xrdp)"
echo "[CHECK] sesman: $(command -v xrdp-sesman)"

# Start session manager
echo "[START] XRDP Session Manager"

xrdp-sesman --nodaemon \
    >> /var/log/xrdp-sesman.log 2>&1 &

SESMAN_PID=$!

sleep 2

if ! kill -0 "$SESMAN_PID" 2>/dev/null; then
    cat /var/log/xrdp-sesman.log
    exit 1
fi

# Start XRDP
echo "[START] XRDP Server"

xrdp --nodaemon \
    >> /var/log/xrdp.log 2>&1 &

XRDP_PID=$!

tail -F /var/log/xrdp.log /var/log/xrdp-sesman.log &
TAIL_PID=$!

cleanup() {
    kill "$TAIL_PID" "$XRDP_PID" "$SESMAN_PID" 2>/dev/null || true
}

trap cleanup EXIT

echo "[READY] Kali Linux RDP running on port 3389"

wait "$XRDP_PID"
