FROM kalilinux/kali-rolling

ENV DEBIAN_FRONTEND=noninteractive

# Install SSH, Cloudflared, dan Python (buat HTTP server bohongan)
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       locales openssh-server wget ca-certificates python3 \
    && localedef -i en_US -c -f UTF-8 en_US.UTF-8 \
    && wget -q \
       https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
       -O /usr/local/bin/cloudflared \
    && chmod +x /usr/local/bin/cloudflared \
    && rm -rf /var/lib/apt/lists/*

# Konfigurasi SSH
RUN mkdir -p /run/sshd \
    && echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config \
    && echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config

# Script Startup
# 1. Set password root
# 2. Jalanin SSH di background
# 3. Jalanin Cloudflared di background
# 4. Jalanin HTTP server bohongan di port 10000 (biar Render seneng)
RUN printf '%s\n' \
    '#!/bin/bash' \
    'set -e' \
    ': "${ROOT_PASSWORD:?Set ROOT_PASSWORD in Environment Variables}"' \
    ': "${CLOUDFLARE_TUNNEL_TOKEN:?Set CLOUDFLARE_TUNNEL_TOKEN in Environment Variables}"' \
    'echo "root:${ROOT_PASSWORD}" | chpasswd' \
    '/usr/sbin/sshd' \
    'cloudflared tunnel --no-autoupdate run --token "$CLOUDFLARE_TUNNEL_TOKEN" &' \
    'echo "HTTP server bohongan jalan di port 10000"' \
    'python3 -m http.server 10000' \
    > /usr/local/bin/start-vps \
    && chmod +x /usr/local/bin/start-vps

# Buka port 22 (buat SSH) dan 10000 (buat Render)
EXPOSE 22
EXPOSE 10000

CMD ["/usr/local/bin/start-vps"]
