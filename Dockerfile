FROM kalilinux/kali-rolling

ENV DEBIAN_FRONTEND=noninteractive
ENV RDP_USER=kali
ENV XDG_RUNTIME_DIR=/tmp/runtime-kali

RUN apt-get update && apt-get install -y --no-install-recommends \
    xfce4 \
    xfce4-terminal \
    xfce4-goodies \
    xrdp \
    xorgxrdp \
    xorg \
    xserver-xorg \
    xserver-xorg-core \
    xserver-xorg-legacy \
    xinit \
    x11-xserver-utils \
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
    ssl-cert \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY start.sh /start.sh

RUN sed -i 's/\r$//' /start.sh \
    && chmod +x /start.sh

EXPOSE 3389

HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
    CMD pgrep -x xrdp > /dev/null && pgrep -x xrdp-sesman > /dev/null || exit 1

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/bin/bash", "/start.sh"]
