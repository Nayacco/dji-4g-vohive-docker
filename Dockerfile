# syntax=docker/dockerfile:1

FROM ubuntu:24.04

ARG TARGETARCH
ARG DEBIAN_FRONTEND=noninteractive

LABEL org.opencontainers.image.source="https://github.com/Nayacco/dji-4g-vohive-docker" \
      org.opencontainers.image.description="VoHive for the DJI 4G / Quectel EG25-G modem" \
      org.opencontainers.image.version="1.5.5"

ENV TZ=Asia/Shanghai \
    CONFIG_PATH=/opt/vohive/config/config.yaml

RUN test "$TARGETARCH" = "amd64" || \
      { echo >&2 "VoHive's bundled binary only supports linux/amd64"; exit 1; } \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
      ca-certificates \
      pciutils \
      socat \
      tzdata \
      usbutils \
    && rm -rf /var/lib/apt/lists/*

COPY vohive-backup.tar.gz /tmp/vohive-backup.tar.gz

RUN tar -xzf /tmp/vohive-backup.tar.gz -C /tmp \
    && echo "fa6d3fb073bc7d0e746637a9b2b58f80e5cd23e248865d05eea2ba7dc0569d83  /tmp/vohive-backup/vohive" | sha256sum -c - \
    && install -d /opt/vohive/bin /opt/vohive/config /opt/vohive/data /opt/vohive/logs /usr/share/vohive \
    && install -m 0755 /tmp/vohive-backup/vohive /opt/vohive/bin/vohive \
    && install -m 0644 /tmp/vohive-backup/mcc-mnc-table.json /opt/vohive/data/mcc-mnc-table.json \
    && install -m 0644 /tmp/vohive-backup/mcc-mnc-table.json /usr/share/vohive/mcc-mnc-table.json \
    && rm -rf /tmp/vohive-backup /tmp/vohive-backup.tar.gz

COPY docker/config.yaml /usr/share/vohive/config.yaml
COPY --chmod=0755 docker/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

WORKDIR /opt/vohive
EXPOSE 7575
STOPSIGNAL SIGTERM
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
