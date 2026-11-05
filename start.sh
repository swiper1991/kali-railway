
#!/bin/bash
set -e

RDP_USER="${RDP_USER:-kali}"
RDP_PASSWORD="${RDP_PASSWORD:?RDP_PASSWORD belum diatur}"

useradd -m -s /bin/bash "$RDP_USER" 2>/dev/null || true

echo "$RDP_USER:$RDP_PASSWORD" | chpasswd
usermod -aG sudo "$RDP_USER"

mkdir -p "/home/$RDP_USER"

cat > "/home/$RDP_USER/.xsession" <<'EOF'
#!/bin/bash
exec dbus-run-session -- startxfce4
EOF

chmod +x "/home/$RDP_USER/.xsession"
chown "$RDP_USER:$RDP_USER" "/home/$RDP_USER/.xsession"

mkdir -p /var/run/dbus /var/run/xrdp /var/log/xrdp

echo "[CHECK] dbus-daemon: $(command -v dbus-daemon)"
echo "[CHECK] xrdp: $(command -v xrdp)"
echo "[CHECK] xrdp-sesman: $(command -v xrdp-sesman)"

dbus-daemon --system --fork

echo "[START] XRDP Session Manager"
xrdp-sesman --nodaemon &

sleep 2

echo "[START] XRDP Server"
exec xrdp --nodaemon
