# syntax=docker/dockerfile:1.7

FROM ghcr.io/linuxserver/baseimage-debian:trixie

ARG BUILD_DATE
ARG VERSION=dev
ARG SUNSHINE_VERSION=2026.516.143833
ARG SUNSHINE_SHA256=b9b65f2be93b3e30be0710a940a616b1381da5bc6d858dce33bc0094d7fd4131
ARG UMU_VERSION=1.4.4
ARG UMU_SHA256=602c4ac7210a54b835530f927b10c2781e51e294b1cf46448006e48fae66f232
ARG DWARFS_VERSION=0.15.7
ARG DWARFS_SHA256=4dc3b756af88ede837eb3f27fbb5f2f0dbb83d7c9933a1d3be9216d2069d2f5f

LABEL org.opencontainers.image.title="steam-wayland" \
      org.opencontainers.image.description="Wayland-first Steam and Moonlight gaming container" \
      org.opencontainers.image.source="https://github.com/remominor/steam-wayland" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.licenses="MIT"

ENV HOME=/config \
    XDG_CONFIG_HOME=/config/.config \
    XDG_DATA_HOME=/config/.local/share \
    XDG_CACHE_HOME=/config/.cache \
    XDG_RUNTIME_DIR=/run/user/911 \
    WAYLAND_DISPLAY=wayland-0 \
    DISPLAY=:0 \
    XDG_SESSION_TYPE=wayland \
    XDG_CURRENT_DESKTOP=labwc \
    XDG_SESSION_DESKTOP=labwc \
    LIBSEAT_BACKEND=seatd \
    SEATD_VTBOUND=0 \
    WLR_BACKENDS=headless,libinput \
    WLR_RENDERER=auto \
    WLR_LIBINPUT_NO_DEVICES=1 \
    XDG_SEAT=seat0 \
    DRI_NODE=/dev/dri/renderD128 \
    DEFAULT_MODE=1920x1080@60 \
    ENABLE_FLATPAK=false \
    NVIDIA_DRIVER_CAPABILITIES=all \
    STEAM_ARGS="-gamepadui -steamos3"

RUN \
  dpkg --add-architecture i386 && \
  apt-get update && \
  apt-get install -y --no-install-recommends \
    adwaita-icon-theme \
    bash \
    bubblewrap \
    ca-certificates \
    curl \
    dbus \
    dbus-x11 \
    evtest \
    flatpak \
    foot \
    fuse3 \
    fuse-overlayfs \
    fuzzel \
    jq \
    labwc \
    libcap2-bin \
    libegl1:i386 \
    libgbm1:i386 \
    libgl1:i386 \
    libgl1-mesa-dri:i386 \
    libinput-tools \
    libpulse0:i386 \
    libvulkan1:i386 \
    mesa-utils \
    mesa-vulkan-drivers \
    mesa-vulkan-drivers:i386 \
    pipewire \
    pipewire-alsa \
    pipewire-pulse \
    pulseaudio-utils \
    seatd \
    steam-libs \
    steam-libs-i386 \
    swaybg \
    thunar \
    udev \
    unzip \
    vulkan-tools \
    waybar \
    wireplumber \
    wlr-randr \
    xdg-utils \
    xwayland \
    zenity && \
  curl -fsSL -o /tmp/sunshine.deb \
    "https://github.com/LizardByte/Sunshine/releases/download/v${SUNSHINE_VERSION}/sunshine-debian-trixie-amd64.deb" && \
  echo "${SUNSHINE_SHA256}  /tmp/sunshine.deb" | sha256sum -c - && \
  mkdir -p /tmp/sunshine-package && \
  dpkg-deb -R /tmp/sunshine.deb /tmp/sunshine-package && \
  printf '#!/bin/sh\nexit 0\n' > /tmp/sunshine-package/DEBIAN/postinst && \
  chmod 755 /tmp/sunshine-package/DEBIAN/postinst && \
  dpkg-deb -b /tmp/sunshine-package /tmp/sunshine-container.deb && \
  apt-get install -y --no-install-recommends /tmp/sunshine-container.deb && \
  curl -fsSL -o /tmp/umu.deb \
    "https://github.com/Open-Wine-Components/umu-launcher/releases/download/${UMU_VERSION}/python3-umu-launcher_${UMU_VERSION}-1_amd64_debian-13.deb" && \
  echo "${UMU_SHA256}  /tmp/umu.deb" | sha256sum -c - && \
  apt-get install -y --no-install-recommends /tmp/umu.deb && \
  curl -fsSL -o /tmp/steam.deb https://cdn.fastly.steamstatic.com/client/installer/steam.deb && \
  mkdir -p /tmp/steam-package && \
  dpkg-deb -R /tmp/steam.deb /tmp/steam-package && \
  printf '#!/bin/sh\nexit 0\n' > /tmp/steam-package/DEBIAN/postinst && \
  chmod 755 /tmp/steam-package/DEBIAN/postinst && \
  dpkg-deb -b /tmp/steam-package /tmp/steam-container.deb && \
  apt-get install -y --no-install-recommends /tmp/steam-container.deb && \
  curl -fsSL -o /tmp/dwarfs.tar.xz \
    "https://github.com/mhx/dwarfs/releases/download/v${DWARFS_VERSION}/dwarfs-${DWARFS_VERSION}-Linux-x86_64.tar.xz" && \
  echo "${DWARFS_SHA256}  /tmp/dwarfs.tar.xz" | sha256sum -c - && \
  tar -xJf /tmp/dwarfs.tar.xz --strip-components=1 -C /usr/local && \
  (getent group seat >/dev/null || groupadd --system seat) && \
  usermod -a -G audio,input,render,seat,video abc && \
  mkdir -p /config /defaults /mnt/games /run/user/911 && \
  chmod 700 /run/user/911 && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/* /tmp/*

COPY root/ /
COPY scripts/ /usr/local/bin/

RUN chmod -R a+rX /defaults && \
    find /etc/s6-overlay/s6-rc.d /usr/local/bin -type f \( -name run -o -name '*.sh' \) -exec chmod 755 {} + && \
    setcap cap_sys_admin,cap_sys_nice+p /usr/bin/sunshine

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD ["/usr/local/bin/healthcheck.sh"]

VOLUME ["/config", "/mnt/games"]

EXPOSE 47984/tcp 47989/tcp 47990/tcp 48010/tcp \
       47998/udp 47999/udp 48000/udp 48002/udp 48010/udp

ENTRYPOINT ["/init"]
