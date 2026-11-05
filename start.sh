
#!/bin/bash
set -e

RDP_USER="${RDP_USER:-kali}"
RDP_PASSWORD="${RDP_PASSWORD:-}"

if [ -z "$RDP_PASSWORD" ]; then
    echo "ERROR: RDP_PASSWORD belum diatur!"
    exit 1
fi

if ! id "$RDP_USER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$RDP_USER"
fi

echo "$RDP_USER:$RDP_PASSWORD" | chpasswd
usermod -aG sudo "$RDP_USER"

echo "startxfce4" > "/home/$RDP_USER/.xsession"
chown "$RDP_USER:$RDP_USER" "/home/$RDP_USER/.xsession"

service xrdp-sesman start

echo "Kali Linux RDP is running on port 3389"

exec xrdp --nodaemon
