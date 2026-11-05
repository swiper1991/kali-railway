#!/bin/bash
set -Eeuo pipefail

RDP_USER="${RDP_USER:-kali}"
RDP_PASSWORD="${RDP_PASSWORD:?RDP_PASSWORD belum diatur}"
RDP_PORT="${RDP_PORT:-3389}"

echo "[INIT] Starting Kali RDP..."

# 1. Create user
if ! id "$RDP_USER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$RDP_USER"
fi
echo "$RDP_USER:$RDP_PASSWORD" | chpasswd
usermod -aG sudo "$RDP_USER"
usermod -aG ssl-cert "$RDP_USER" 2>/dev/null || true
adduser xrdp ssl-cert 2>/dev/null || true

HOME_DIR="$(eval echo ~"$RDP_USER")"
mkdir -p "$HOME_DIR"
chown "$RDP_USER:$RDP_USER" "$HOME_DIR"

# 2. BUNUH PROSES NYANGKUT & BERSIHIN LOCK (INI KUNCI UTAMANYA)
pkill -9 xrdp 2>/dev/null || true
pkill -9 xrdp-sesman 2>/dev/null || true
pkill -9 Xorg 2>/dev/null || true
rm -rf /run/xrdp/sockdir/sesman.socket* 2>/dev/null || true
rm -rf /tmp/.X11-unix/* 2>/dev/null || true
rm -rf /tmp/.xrdp/* 2>/dev/null || true

# 3. Prepare dirs & permissions
mkdir -p /var/run/dbus /run/xrdp/sockdir /var/log/xrdp /tmp/runtime-kali
chown -R xrdp:xrdp /run/xrdp
chmod 777 /run/xrdp /run/xrdp/sockdir
chown "$RDP_USER:$RDP_USER" /tmp/runtime-kali
chmod 700 /tmp/runtime-kali

# 4. Fix Xorg wrapper
cat > /etc/X11/Xwrapper.config <<EOF
allowed_users=anybody
needs_root_rights=no
EOF

# 5. Start DBus
if [ ! -S /var/run/dbus/system_bus_socket ]; then
    dbus-daemon --system --fork || true
fi

# 6. SSL Cert
if [ ! -f /etc/xrdp/railway.crt ]; then
    openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout /etc/xrdp/railway.key \
        -out /etc/xrdp/railway.crt \
        -days 3650 -subj "/CN=railway-kali" 2>/dev/null
fi
chown xrdp:xrdp /etc/xrdp/railway.key /etc/xrdp/railway.crt
chmod 600 /etc/xrdp/railway.key
chmod 644 /etc/xrdp/railway.crt

# 7. Config files
sed -i \
    -e "s|^certificate=.*|certificate=/etc/xrdp/railway.crt|" \
    -e "s|^key_file=.*|key_file=/etc/xrdp/railway.key|" \
    -e "s|^port=.*|port=$RDP_PORT|" \
    /etc/xrdp/xrdp.ini
sed -i '/^ip=/d' /etc/xrdp/xrdp.ini
sed -i '/^runtime_user=/d' /etc/xrdp/xrdp.ini
sed -i '/^runtime_group=/d' /etc/xrdp/xrdp.ini

# 8. Config sesman
groupadd -f xrdp
sed -i '/^\[Globals\]/a SessionSockdirGroup=xrdp' /etc/xrdp/sesman.ini
sed -i 's|param=Xorg|param=/usr/lib/xorg/Xorg|' /etc/xrdp/sesman.ini

# 9. XFCE session
cat > "$HOME_DIR/.xsession" <<'EOF'
#!/bin/bash
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR
exec startxfce4
EOF
chmod +x "$HOME_DIR/.xsession"
chown "$RDP_USER:$RDP_USER" "$HOME_DIR/.xsession"

cat > /etc/xrdp/startwm.sh <<'EOF'
#!/bin/sh
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR
if [ -r /etc/profile ]; then . /etc/profile; fi
if [ -r ~/.profile ]; then . ~/.profile; fi
exec startxfce4
EOF
chmod +x /etc/xrdp/startwm.sh

# 10. Start daemons
echo "[START] XRDP Session Manager..."
xrdp-sesman --nodaemon >> /var/log/xrdp-sesman.log 2>&1 &
SESMAN_PID=$!
sleep 2
if ! kill -0 "$SESMAN_PID" 2>/dev/null; then cat /var/log/xrdp-sesman.log; exit 1; fi

echo "[START] XRDP Server..."
xrdp --nodaemon >> /var/log/xrdp.log 2>&1 &
XRDP_PID=$!
sleep 2
if ! kill -0 "$XRDP_PID" 2>/dev/null; then cat /var/log/xrdp.log; kill "$SESMAN_PID"; exit 1; fi

# 11. Tail logs
tail -F /var/log/xrdp.log /var/log/xrdp-sesman.log &
TAIL_PID=$!

cleanup() {
    kill "$TAIL_PID" "$XRDP_PID" "$SESMAN_PID" 2>/dev/null || true
    wait 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "[READY] Kali RDP up on port $RDP_PORT"
wait "$XRDP_PID"
