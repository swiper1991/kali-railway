#!/bin/bash
set -Eeuo pipefail

RDP_USER="${RDP_USER:-kali}"
RDP_PASSWORD="${RDP_PASSWORD:?RDP_PASSWORD belum diatur}"

# 1. Bikin user & set password
if ! id "$RDP_USER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$RDP_USER"
fi
echo "$RDP_USER:$RDP_PASSWORD" | chpasswd
usermod -aG sudo "$RDP_USER"
usermod -aG ssl-cert "$RDP_USER" 2>/dev/null || true
adduser xrdp ssl-cert 2>/dev/null || true

# 2. Setup folder & permission
HOME_DIR="$(eval echo ~"$RDP_USER")"
mkdir -p "$HOME_DIR"
chown "$RDP_USER:$RDP_USER" "$HOME_DIR"
touch "$HOME_DIR/.Xauthority"
chown "$RDP_USER:$RDP_USER" "$HOME_DIR/.Xauthority"
chmod 600 "$HOME_DIR/.Xauthority"

# 3. Bikin XFCE session
cat > "$HOME_DIR/.xsession" <<'EOF'
#!/bin/bash
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR
exec startxfce4
EOF
chmod +x "$HOME_DIR/.Xauthority" "$HOME_DIR/.xsession"
chown "$RDP_USER:$RDP_USER" "$HOME_DIR/.xsession"

# 4. Setup Xorg Wrapper & Dir
cat > /etc/X11/Xwrapper.config <<EOF
allowed_users=anybody
needs_root_rights=yes
EOF

rm -rf /run/xrdp /var/run/xrdp /tmp/.X11-unix /tmp/.xrdp 2>/dev/null || true
mkdir -p /run/xrdp/sockdir /tmp/.X11-unix
chown -R xrdp:xrdp /run/xrdp /tmp/.X11-unix
chmod 777 /run/xrdp /run/xrdp/sockdir /tmp/.X11-unix

# 5. DBus (TAMBAHIN mkdir -p /run/dbus)
mkdir -p /run/dbus
if [ ! -S /run/dbus/system_bus_socket ]; then
    dbus-daemon --system --fork || true
fi

# 6. SSL
if [ ! -f /etc/xrdp/railway.crt ]; then
    openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout /etc/xrdp/railway.key \
        -out /etc/xrdp/railway.crt \
        -days 3650 -subj "/CN=railway-kali" 2>/dev/null
fi
chown xrdp:xrdp /etc/xrdp/railway.key /etc/xrdp/railway.crt
chmod 600 /etc/xrdp/railway.key
chmod 644 /etc/xrdp/railway.crt

sed -i "s|^certificate=.*|certificate=/etc/xrdp/railway.crt|" /etc/xrdp/xrdp.ini
sed -i "s|^key_file=.*|key_file=/etc/xrdp/railway.key|" /etc/xrdp/xrdp.ini
sed -i "s|^port=.*|port=3389|" /etc/xrdp/xrdp.ini

# 7. SESMAN CONFIG
sed -i 's|param=Xorg|param=/usr/lib/xorg/Xorg|g' /etc/xrdp/sesman.ini
grep -q "SessionSockdirGroup" /etc/xrdp/sesman.ini || sed -i '/^\[Globals\]/a SessionSockdirGroup=xrdp' /etc/xrdp/sesman.ini

# 8. START
echo "[START] Running XRDP..."
xrdp-sesman --nodaemon &
xrdp --nodaemon
