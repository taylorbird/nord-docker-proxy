# NordLayer client + a SOCKS5 proxy. Only traffic sent to the proxy rides the
# VPN; the Mac itself stays off it.
#
# Pinned on purpose: the base image by digest, the NordLayer package by sha256.
# NordLayer only publishes a "latest" URL, so a new release makes the build
# fail here instead of silently running a binary nobody checked. To take a new
# release: download it, check it, update NORDLAYER_SHA256_*, `nord-docker-proxy rebuild`.
FROM ubuntu:24.04@sha256:fe81560990fae86dc4743202b2cb4d3df98d0bcf949173cecef15ce1127ef852
ARG TARGETARCH
# nordlayer 3.6.0, checked 2026-10-30
ARG NORDLAYER_SHA256_arm64=00dbf8ea2ad455c1bfb5864a69434fa51e5c0dfa4b527f116288610e68dba211
ARG NORDLAYER_SHA256_amd64=037ff798826c3a453bd77b2ccd1e811c280a4205347a4a41a4f97791c3a3a9d2
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl iproute2 microsocks nftables \
 && curl -fsSL -o /tmp/nordlayer.deb \
      "https://downloads.nordlayer.com/linux/latest/debian/latest/nordlayer_latest_${TARGETARCH}.deb" \
 && eval "expected=\$NORDLAYER_SHA256_${TARGETARCH}" \
 && echo "${expected}  /tmp/nordlayer.deb" | sha256sum -c - \
 && apt-get install -y /tmp/nordlayer.deb \
 && test -x /usr/sbin/nordlayerd \
 && rm -rf /tmp/nordlayer.deb /var/lib/apt/lists/*
COPY entrypoint.sh /
RUN chmod 755 /entrypoint.sh
EXPOSE 1080
ENTRYPOINT ["/entrypoint.sh"]
