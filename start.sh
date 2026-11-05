FROM kalilinux/kali-rolling

ENV DEBIAN_FRONTEND=noninteractive
ENV RDP_USER=kali

RUN apt-get update && apt-get install -y \
    xfce4 \
    xfce4-terminal \
    xrdp \
    xorgxrdp \
    xserver-xorg-core \
    dbus \
    dbus-x11 \
    xauth \
    sudo \
    nano \
    curl \
    wget \
    git \
    firefox-esr \
    procps \
    iproute2 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY start.sh /start.sh

RUN sed -i 's/\r$//' /start.sh \
    && chmod +x /start.sh

EXPOSE 3389

CMD ["/bin/bash", "/start.sh"]
