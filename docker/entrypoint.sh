#!/bin/bash
# Runs nordlayerd the way its systemd unit does (user nordlayer, the unit's
# capability set) without systemd, plus two proxies into the VPN: microsocks
# (SOCKS5, :1080) and tinyproxy (HTTP, :8080). If any of them exits, the
# container exits, so a dead tunnel never looks like a live proxy.
#
# The proxies are a doorway into the VPN, nothing more: what's reachable
# behind it is the VPN's business. The one rule here is that proxied traffic
# goes through the tunnel or nowhere.
set -euo pipefail

mkdir -p /run/nordlayer /var/lib/nordlayer
# Recursive: the saved login on the volume outlives the image, and a rebuild can
# give the `nordlayer` user a different UID (e.g. when another package's system
# user is created first), which would leave the login unreadable.
chown -R nordlayer:nordlayer /run/nordlayer /var/lib/nordlayer
cd /run/nordlayer

# --- kill switch for the proxies -------------------------------------------
# Both proxies run as `nobody`; their new outbound connections leave through
# the VPN tunnel or not at all. NordLayer's own kill switch can't be used: it
# also drops the Mac's inbound connections to the proxies. Replies to the
# Mac's connections and loopback (Docker's DNS) stay allowed. The NordLayer
# daemon and root are untouched.
nft -f - <<'NFT'
table inet proxy_firewall {
  chain output {
    type filter hook output priority filter; policy accept;
    meta skuid != "nobody" accept
    ct direction reply accept
    oifname "lo" accept
    oifname { "nlx0", "ovpn0" } accept
    reject with icmpx admin-prohibited
  }
}
NFT

setpriv --reuid=nordlayer --regid=nordlayer --init-groups \
  --inh-caps=+net_admin,+net_raw,+net_bind_service,+ipc_lock \
  --ambient-caps=+net_admin,+net_raw,+net_bind_service,+ipc_lock \
  /usr/sbin/nordlayerd -config /etc/nordlayer/config.hcl &

# Both listen on all interfaces inside the container; compose publishes them
# on the Mac's 127.0.0.1 only.
setpriv --reuid=nobody --regid=nogroup --clear-groups \
  microsocks -i 0.0.0.0 -p 1080 &

# HTTP proxy for clients that can't use SOCKS (Chrome with a proxy flag, most
# CLIs via HTTP(S)_PROXY). tinyproxy drops to `nobody` itself (User/Group).
tinyproxy -d -c /etc/tinyproxy/ndp.conf &

# Optional max uptime: the container stops itself and, with restart "no",
# stays down until the next `up`.
if [[ "${MAX_HOURS:-0}" =~ ^[0-9]+$ ]] && (( MAX_HOURS > 0 )); then
  sleep $(( MAX_HOURS * 3600 )) &
fi

wait -n
exit 1
