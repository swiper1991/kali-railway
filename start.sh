#!/bin/bash
set -Eeuo pipefail

# ============================================================
# Railway-compatible XRDP bootstrap for Kali Linux
# FIX: Socket permission & session fallback
# ============================================================

RDP_USER="${RDP_USER:-kali}"
RDP_PASSWORD="${RDP_PASSWORD:?RDP_PASSWORD belum diatur}"
RDP_PORT="${RDP_PORT:-3389}"

echo "[INIT] Preparing Kali Linux RDP environment..."
echo "[INIT] User: $RDP_USER | Port: $RDP_PORT"

# 1. Create user
if ! id "$RDP_USER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$RDP_USER"
fi

echo "$RDP_USER:$RDP_PASSWORD" | chpasswd
usermod -aG sudo "$RDP_USER"
usermod -aG ssl-cert "$RDP_USER" 2>/dev/null || true
adduser xrdp ssl-cert 2>/dev/null || true

# 2. FIX UTAMA: Paksa group & permission
groupadd -f xrdp
usermod -aG xrdp xrdp 2>/dev/null || true
usermod -aG xrdp "$RDP_USER" 2>/dev/null || true

HOME_DIR="$(eval echo ~"$RDP_USER")"
mkdir -p "$HOME_DIR"
chown "$RDP_USER:$RDP_USER" "$HOME_DIR"

# 3. Siapkan direktori runtime (HAPUS YANG LAMA)
rm -rf /var/run/xrdp /run/xrdp /tmp/.X11-unix /tmp/.xrdp 2>/dev/null || true

mkdir -p /var/run/dbus
mkdir -p /var/run/xrdp/sockdir
mkdir -p /var/log/xrdp
mkdir -p /tmp/runtime-kali

# 4. Permission Mutlak buat Socket
chown -R xrdp:xrdp /var/run/xrdp
chmod 777 /var/run/xrdp
chmod 777 /var/run/xrdp/sockdir

chown "$RDP_USER:$RDP_USER" /tmp/runtime-kali
chmod 700 /tmp/runtime-kali

# 5. Fix Xorg Wrapper
cat > /etc/X11/Xwrapper.config <<EOF
allowed_users=anybody
needs_root_rights=no
EOF

# 6. DBus
if [ ! -S /var/run/dbus/system_bus_socket ]; then
    dbus-daemon --system --fork || true
fi

# 7. SSL Cert
if [ ! -f /etc/xrdp/railway.crt ]; then
    openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout /etc/xrdp/railway.key \
        -out /etc/xrdp/railway.crt \
        -days 3650 -subj "/CN=railway-kali" 2>/dev/null
fi
chown xrdp:xrdp /etc/xrdp/railway.key /etc/xrdp/railway.crt
chmod 600 /etc/xrdp/railway.key
chmod 644 /etc/xrdp/railway.crt

# 8. Config XRDP
sed -i \
    -e "s|^certificate=.*|certificate=/etc/xrdp/railway.crt|" \
    -e "s|^key_file=.*|key_file=/etc/xrdp/railway.key|" \
    -e "s|^port=.*|port=$RDP_PORT|" \
    /etc/xrdp/xrdp.ini
sed -i '/^ip=/d' /etc/xrdp/xrdp.ini

# 9. Config sesman (Paksa SocketDir)
sed -i '/^\[Globals\]/a SessionSockdirGroup=xrdp' /etc/xrdp/sesman.ini
sed -i "s|^ListenAddress=.*|ListenAddress=127.0.0.1|" /etc/xrdp/sesman.ini
sed -i "s|^ListenPort=.*|ListenPort=3350|" /etc/xrdp/sesman.ini

# 10. Xauthority & Session
touch "$HOME_DIR/.Xauthority"
chown "$RDP_USER:$RDP_USER" "$HOME_DIR/.Xauthority"
chmod 600 "$HOME_DIR/.Xauthority"

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

# 11. Start Sesman
echo "[START] XRDP Session Manager..."
xrdp-sesman --nodaemon >> /var/log/xrdp-sesman.log 2>&1 &
SESMAN_PID=$!
sleep 2

if ! kill -0 "$SESMAN_PID" 2>/dev/null; then
    echo "[FATAL] xrdp-sesman crashed."
    cat /var/log/xrdp-sesman.log
    exit 1
fi

# 12. Start XRDP
echo "[START] XRDP Server on port $RDP_PORT..."
xrdp --nodaemon >> /var/log/xrdp.log 2>&1 &
XRDP_PID=$!
sleep 2

if ! kill -0 "$XRDP_PID" 2>/dev/null; then
    echo "[FATAL] xrdp crashed."
    cat /var/log/xrdp.log
    kill "$SESMAN_PID" 2>/dev/null || true
    exit 1
fi

tail -F /var/log/xrdp.log /var/log/xrdp-sesman.log &
TAIL_PID=$!

cleanup() {
    kill "$TAIL_PID" "$XRDP_PID" "$SESMAN_PID" 2>/dev/null || true
    wait 2>/dev/null || true
}
trap cleanup EXIT INT TERM

wait "$XRDP_PID"
