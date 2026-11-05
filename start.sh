
#!/bin/bash
set -e

RDP_USER="${RDP_USER:-kali}"
RDP_PASSWORD="${RDP_PASSWORD:?RDP_PASSWORD belum diatur}"

if ! id "$RDP_USER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$RDP_USER"
fi

echo "$RDP_USER:$RDP_PASSWORD" | chpasswd
usermod -aG sudo "$RDP_USER"

mkdir -p "/home/$RDP_USER"

cat > "/home/$RDP_USER/.xsession" <<'EOF'
#!/bin/bash
exec dbus-run-session -- startxfce4
EOF

chmod +x "/home/$RDP_USER/.xsession"
chown "$RDP_USER:$RDP_USER" "/home/$RDP_USER/.xsession"

mkdir -p /var/run/dbus
dbus-daemon --system --fork || true

echo "[START] Starting XRDP Session Manager..."

/usr/sbin/xrdp-sesman --nodaemon &
SESMAN_PID=$!

sleep 2

if ! kill -0 "$SESMAN_PID" 2>/dev/null; then
    echo "[ERROR] XRDP Session Manager failed!"
    exit 1
fi

echo "[START] Starting XRDP Server..."

exec /usr/sbin/xrdp --nodaemon
