
FROM kalilinux/kali-rolling

ENV DEBIAN_FRONTEND=noninteractive

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
    && command -v dbus-daemon \
    && command -v xrdp \
    && command -v xrdp-sesman \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY start.sh /start.sh

RUN chmod +x /start.sh

EXPOSE 3389

CMD ["/start.sh"]
