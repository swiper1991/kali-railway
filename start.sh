#!/bin/bash
set -Eeuo pipefail

# ============================================================
# Railway-compatible XRDP bootstrap for Kali Linux
# ============================================================

RDP_USER="${RDP_USER:-kali}"
RDP_PASSWORD="${RDP_PASSWORD:?RDP_PASSWORD belum diatur}"
RDP_PORT="${RDP_PORT:-3389}"

echo "[INIT] Preparing Kali Linux RDP environment..."
echo "[INIT] User: $RDP_USER | Port: $RDP_PORT"

# ------------------------------------------------------------
# 1. Create user if not exists
# ------------------------------------------------------------
if ! id "$RDP_USER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$RDP_USER"
    echo "[USER] Created user: $RDP_USER"
fi

echo "$RDP_USER:$RDP_PASSWORD" | chpasswd
usermod -aG sudo "$RDP_USER"
usermod -aG ssl-cert "$RDP_USER" 2>/dev/null || true
adduser xrdp ssl-cert 2>/dev/null || true

HOME_DIR="$(eval echo ~"$RDP_USER")"
mkdir -p "$HOME_DIR"
chown "$RDP_USER:$RDP_USER" "$HOME_DIR"

# ------------------------------------------------------------
# 2. Prepare runtime directories
# ------------------------------------------------------------
mkdir -p /var/run/dbus
mkdir -p /var/run/xrdp
mkdir -p /var/run/xrdp/sockdir
mkdir -p /var/log/xrdp
mkdir -p /tmp/runtime-kali

# FIX KRUSIAL: Pastikan permission socket bener
chown xrdp:xrdp /var/run/xrdp
chown xrdp:xrdp /var/run/xrdp/sockdir
chmod 755 /var/run/xrdp/sockdir

chown "$RDP_USER:$RDP_USER" /tmp/runtime-kali
chmod 700 /tmp/runtime-kali

# ------------------------------------------------------------
# 3. Clean stale session files
# ------------------------------------------------------------
rm -rf /tmp/.X11-unix/* 2>/dev/null || true
rm -rf /tmp/.xrdp/* 2>/dev/null || true

# ------------------------------------------------------------
# 4. Fix Xorg for container environment
# ------------------------------------------------------------
echo "[FIX] Configuring Xorg for container..."

cat > /etc/X11/Xwrapper.config <<EOF
allowed_users=anybody
needs_root_rights=no
EOF

if ! dpkg -l | grep -q xorgxrdp; then
    echo "[FIX] Installing xorgxrdp..."
    apt-get update && apt-get install -y xorgxrdp
fi

# ------------------------------------------------------------
# 5. Start system DBus
# ------------------------------------------------------------
if [ ! -S /var/run/dbus/system_bus_socket ]; then
    echo "[DBUS] Starting system bus..."
    dbus-daemon --system --fork || echo "[DBUS] Warn: system bus already running"
fi

# ------------------------------------------------------------
# 6. Generate XRDP SSL certificate
# ------------------------------------------------------------
echo "[SSL] Generating XRDP certificate..."
if [ ! -f /etc/xrdp/railway.crt ] || [ ! -f /etc/xrdp/railway.key ]; then
    openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout /etc/xrdp/railway.key \
        -out /etc/xrdp/railway.crt \
        -days 3650 \
        -subj "/CN=railway-kali" 2>/dev/null
fi

chown xrdp:xrdp /etc/xrdp/railway.key
chown xrdp:xrdp /etc/xrdp/railway.crt
chmod 600 /etc/xrdp/railway.key
chmod 644 /etc/xrdp/railway.crt

# ------------------------------------------------------------
# 7. Configure XRDP (HAPUS ip= biar gak error)
# ------------------------------------------------------------
sed -i \
    -e "s|^certificate=.*|certificate=/etc/xrdp/railway.crt|" \
    -e "s|^key_file=.*|key_file=/etc/xrdp/railway.key|" \
    -e "s|^port=.*|port=$RDP_PORT|" \
    /etc/xrdp/xrdp.ini

# Hapus baris 'ip=' yang bikin error
sed -i '/^ip=/d' /etc/xrdp/xrdp.ini

# ------------------------------------------------------------
# 8. Configure sesman (INI YANG BIKIN XORG GAGAL START)
# ------------------------------------------------------------
# Tambahin SessionSockdirGroup=xrdp di [Globals]
if ! grep -q "SessionSockdirGroup" /etc/xrdp/sesman.ini; then
    sed -i '/^\[Globals\]/a SessionSockdirGroup=xrdp' /etc/xrdp/sesman.ini
fi

# ------------------------------------------------------------
# 9. Xauthority
# ------------------------------------------------------------
touch "$HOME_DIR/.Xauthority"
chown "$RDP_USER:$RDP_USER" "$HOME_DIR/.Xauthority"
chmod 600 "$HOME_DIR/.Xauthority"

# ------------------------------------------------------------
# 10. XFCE session for user
# ------------------------------------------------------------
cat > "$HOME_DIR/.xsession" <<'EOF'
#!/bin/bash
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR
exec startxfce4
EOF

chmod +x "$HOME_DIR/.xsession"
chown "$RDP_USER:$RDP_USER" "$HOME_DIR/.xsession"

# ------------------------------------------------------------
# 11. XRDP window manager starter
# ------------------------------------------------------------
cat > /etc/xrdp/startwm.sh <<'EOF'
#!/bin/sh
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR
if [ -r /etc/profile ]; then . /etc/profile; fi
if [ -r ~/.profile ]; then . ~/.profile; fi
exec startxfce4
EOF

chmod +x /etc/xrdp/startwm.sh

# ------------------------------------------------------------
# 12. Debug info
# ------------------------------------------------------------
echo "[CHECK] dbus-daemon : $(command -v dbus-daemon || echo MISSING)"
echo "[CHECK] xrdp        : $(command -v xrdp || echo MISSING)"
echo "[CHECK] xrdp-sesman : $(command -v xrdp-sesman || echo MISSING)"
echo "[CHECK] startxfce4  : $(command -v startxfce4 || echo MISSING)"
echo "[CHECK] Xorg        : $(command -v Xorg || echo MISSING)"

# ------------------------------------------------------------
# 13. Start XRDP session manager
# ------------------------------------------------------------
echo "[START] XRDP Session Manager..."
xrdp-sesman --nodaemon >> /var/log/xrdp-sesman.log 2>&1 &
SESMAN_PID=$!

sleep 2

if ! kill -0 "$SESMAN_PID" 2>/dev/null; then
    echo "[FATAL] xrdp-sesman crashed. Log:"
    cat /var/log/xrdp-sesman.log
    exit 1
fi
echo "[OK] xrdp-sesman running (PID $SESMAN_PID)"

# ------------------------------------------------------------
# 14. Start XRDP server
# ------------------------------------------------------------
echo "[START] XRDP Server on port $RDP_PORT..."
xrdp --nodaemon >> /var/log/xrdp.log 2>&1 &
XRDP_PID=$!

sleep 2

if ! kill -0 "$XRDP_PID" 2>/dev/null; then
    echo "[FATAL] xrdp crashed. Log:"
    cat /var/log/xrdp.log
    kill "$SESMAN_PID" 2>/dev/null || true
    exit 1
fi
echo "[OK] xrdp running (PID $XRDP_PID)"

# ------------------------------------------------------------
# 15. Tail logs + cleanup handler
# ------------------------------------------------------------
tail -F /var/log/xrdp.log /var/log/xrdp-sesman.log &
TAIL_PID=$!

cleanup() {
    echo "[SHUTDOWN] Cleaning up..."
    kill "$TAIL_PID" "$XRDP_PID" "$SESMAN_PID" 2>/dev/null || true
    wait 2>/dev/null || true
}

trap cleanup EXIT INT TERM

echo "=================================================="
echo "[READY] Kali RDP up on port $RDP_PORT"
echo "[READY] Railway TCP Proxy -> container:$RDP_PORT"
echo "=================================================="

wait "$XRDP_PID"
