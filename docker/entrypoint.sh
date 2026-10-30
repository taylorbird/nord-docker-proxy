#!/bin/bash
# Runs nordlayerd the way its systemd unit does (user nordlayer, the unit's
# capability set) without systemd, plus microsocks on :1080. If either exits,
# the container exits, so a dead tunnel never looks like a live proxy.
set -euo pipefail
: "${PROXY_USER:?}" "${PROXY_PASS:?}" "${ALLOWED_PORTS:?}"

mkdir -p /run/nordlayer /var/lib/nordlayer
chown nordlayer:nordlayer /run/nordlayer /var/lib/nordlayer
cd /run/nordlayer

# --- proxy firewall --------------------------------------------------------
# Rules for the proxy's own traffic only (microsocks runs as `nobody`); the
# NordLayer daemon and root are untouched.
#  - Kill switch for the proxy: new outbound connections leave through the VPN
#    tunnel or not at all. NordLayer's own kill switch can't be used — it also
#    drops the Mac's inbound connections to the proxy.
#  - Destination ports: ALLOWED_PORTS only ("any" lifts the port limit, never
#    the VPN-only rule).
#  - DNS (53) through the tunnel: once connected, NordLayer points resolv.conf
#    at its own resolvers, reached through the tunnel.
#  - Replies to the Mac's connections, and loopback, stay allowed.
if [[ "$ALLOWED_PORTS" == any ]]; then
  port_rule='oifname { "nlx0", "ovpn0" } accept'
else
  [[ "$ALLOWED_PORTS" =~ ^[0-9]+(,[0-9]+)*$ ]] || { echo "ALLOWED_PORTS must be like 27017 or 5432,6379 or any" >&2; exit 1; }
  port_rule="oifname { \"nlx0\", \"ovpn0\" } tcp dport { ${ALLOWED_PORTS} } accept"
fi
nft -f - <<NFT
table inet proxy_firewall {
  chain output {
    type filter hook output priority filter; policy accept;
    meta skuid != "nobody" accept
    ct direction reply accept
    oifname "lo" accept
    ${port_rule}
    oifname { "nlx0", "ovpn0" } meta l4proto { tcp, udp } th dport 53 accept
    reject with icmpx admin-prohibited
  }
}
NFT

setpriv --reuid=nordlayer --regid=nordlayer --init-groups \
  --inh-caps=+net_admin,+net_raw,+net_bind_service,+ipc_lock \
  --ambient-caps=+net_admin,+net_raw,+net_bind_service,+ipc_lock \
  /usr/sbin/nordlayerd -config /etc/nordlayer/config.hcl &

# Listens on all interfaces inside the container; compose publishes it on the
# Mac's 127.0.0.1 only. Username/password required. No -1: it whitelists by
# IP, and under Docker's NAT every client shares one IP.
setpriv --reuid=nobody --regid=nogroup --clear-groups \
  microsocks -i 0.0.0.0 -p 1080 -u "$PROXY_USER" -P "$PROXY_PASS" &
unset PROXY_PASS

# Optional max uptime: the container stops itself and, with restart "no",
# stays down until the next `up`.
if [[ "${MAX_HOURS:-0}" =~ ^[0-9]+$ ]] && (( MAX_HOURS > 0 )); then
  sleep $(( MAX_HOURS * 3600 )) &
fi

wait -n
exit 1
