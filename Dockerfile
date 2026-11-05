FROM kalilinux/kali-rolling

ENV DEBIAN_FRONTEND=noninteractive
ENV RDP_USER=kali

RUN apt-get update && apt-get install -y --no-install-recommends \
    xfce4 \
    xfce4-terminal \
    xfce4-goodies \
    xrdp \
    xorgxrdp \
    xserver-xorg-core \
    xserver-xorg-legacy \
    dbus \
    dbus-x11 \
    xauth \
    openssl \
    sudo \
    nano \
    curl \
    wget \
    git \
    firefox-esr \
    procps \
    iproute2 \
    net-tools \
    tini \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY start.sh /start.sh
RUN sed -i 's/\r$//' /start.sh && chmod +x /start.sh

EXPOSE 3389

# Pake tini biar proses zombie mati bersih
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/bin/bash", "/start.sh"]
