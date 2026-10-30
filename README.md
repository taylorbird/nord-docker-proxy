# nord-docker-proxy

Reach what's behind your NordLayer gateway **without putting your whole Mac on
the VPN.** NordLayer's Linux client runs in a Docker container and is exposed to
your Mac as two local proxies, SOCKS5 on `127.0.0.1:1080` and HTTP on
`127.0.0.1:8080`. Whatever you point at them reaches what the VPN reaches.
Everything else on your Mac keeps its normal connection and speed.

Typical uses: a browser window for internal sites, CLIs and scripts (or AI
agents) that need a service allowlisted to your gateway, a database driver.

> Unofficial. Not affiliated with or endorsed by Nord Security / NordLayer.

## Install

```sh
brew install --cask taylorbird/nord-docker-proxy/nord-docker-proxy
nord-docker-proxy setup
```

Needs Docker Desktop (running) and a NordLayer account that can use SSO
(Google, Okta, Entra ID, OneLogin or JumpCloud). macOS 15+ (it uses the system
`jq`), Apple silicon.

`setup` asks for your NordLayer organization ID, logs you in, and lets you pick
a gateway. The menu bar app, **Nord Docker Proxy**, then shows status,
starts/stops everything and opens a browser on the VPN; its icon is green only
when healthy.

## Use

| | |
|---|---|
| `nord-docker-proxy up [--hours N]` | start; reconnects if still logged in; optional auto-stop |
| `nord-docker-proxy down` | stop and remove the container: nothing reaches the VPN |
| `nord-docker-proxy status [--json]` | container / login / VPN exit / kill switch / both proxies |
| `nord-docker-proxy chrome` | open a separate Chrome profile whose traffic all goes through the VPN |
| `nord-docker-proxy proxy-env` | `export` lines for the shell (below) |
| `nord-docker-proxy login` / `logout` | SSO login (below) / end the session and delete the saved login |
| `nord-docker-proxy connect` / `disconnect` | VPN only; the container stays up |
| `nord-docker-proxy gateways` | gateways your account can use |
| `nord-docker-proxy rebuild` | rebuild the image (after updating the pinned package) |

Healthy means: traffic through the proxy exits at the gateway's address, the
proxies' VPN-only rule is loaded, and both proxies answer.

## Pointing things at the proxies

**A browser:** `nord-docker-proxy chrome` (or *Open Chrome via VPN* in the
menu) opens Chrome with its own profile, so its history and cookies stay
separate and your everyday Chrome stays off the VPN.

**A shell, a CLI, an agent:**

```sh
eval "$(nord-docker-proxy proxy-env)"
```

sets `HTTP_PROXY`/`HTTPS_PROXY` (HTTP proxy), `ALL_PROXY` (SOCKS5) and
`NO_PROXY=localhost,…`, which curl, git, pip, Homebrew and most CLIs honor, plus
`NDP_PROXY_HOST`/`NDP_PROXY_PORT`/`NDP_HTTP_PORT` and `NDP_SOCKS_URL`/`NDP_HTTP_URL`
for code that wants them explicitly.

**MongoDB** (Node driver, with the `socks` package installed next to `mongodb`):

```js
new MongoClient(uri, { proxyHost: '127.0.0.1', proxyPort: 1080 })
```

## Configuration

Every setting is declared in [`compose.yaml`](compose.yaml). Your values live
in `~/.config/nord-docker-proxy/config.env` (written by `setup`, compose
env-file format):

| Setting | |
|---|---|
| `NDP_ORG` | NordLayer organization ID (required) |
| `NDP_GATEWAY` | gateway ID to connect to (required; see `gateways`) |
| `NDP_ACCOUNT` | the only NordLayer email accepted at login (optional) |
| `NDP_MAX_HOURS` | auto-stop after N hours of uptime; `0` = never |
| `NDP_PROXY_PORT` | local SOCKS5 port (default `1080`) |
| `NDP_HTTP_PORT` | local HTTP proxy port (default `8080`) |
| `NDP_STATE_VOLUME` | Docker volume holding the login (default `nord-docker-proxy-state`) |

## Login

Run it in Terminal: `nord-docker-proxy login` (the menu's *Log In in
Terminal…* does the same).

NordLayer's SSO ends by sending the browser to `nordlayer://auth?exchange_token=…`.
On a Mac that link belongs to the NordLayer app (or nothing), so the container
never sees it. `login` picks your SSO method, opens the sign-in page, and
watches the clipboard: on the success page, **right-click "Continue" → Copy
Link** and it continues by itself. If NordLayer then asks for 2FA, it picks the
authenticator app and hands you the code prompt. If NordLayer refuses
(e.g. *"Portal visit delayed by 32s"* after several attempts in a row), it
shows that message; wait and try once more.

Logins last up to your organization's session timeout (NordLayer Control Panel
→ Settings → Security configurations). Clipboard managers and Universal
Clipboard may keep a copy of the link; it is used within about a second.

## Security model

The proxies are a doorway into the VPN. What's reachable behind it is the
VPN's business, so the proxies don't re-restrict it; they add three things:

- **Loopback only**: both proxies are published on `127.0.0.1`, so no other
  device on your network can use them.
- **VPN or nothing**: a firewall inside the container (nftables, for the
  proxies' traffic only) lets their connections out through the VPN tunnel and
  nowhere else, so with the VPN down they reach nothing rather than quietly
  using your normal connection. NordLayer's own kill switch is kept **off** in
  the container (`connect` enforces it): with it on, NordLayer drops every
  inbound connection on the container's interface, which is how your Mac reaches
  the proxies.
- **Your account only**: after login, the account must be in `NDP_ORG` (and be
  `NDP_ACCOUNT` when set), or it is logged out and the saved login deleted, so
  another app can't slip its own login link onto your clipboard. The token
  reaches the container over stdin, never as a process argument.

Compared with putting the whole Mac on the VPN, this is narrower: only what you
point at the proxies goes through. Anything running as you on your Mac can use
them, just as it could use a Mac-wide VPN.

Also: the base image is pinned by digest and the NordLayer `.deb` by sha256
([`docker/Dockerfile`](docker/Dockerfile)), so a new NordLayer release fails
the build until the hash is updated; and the CLI ships inside the signed app,
which verifies its own signature and publisher before running it.

## How it works

`docker/entrypoint.sh` runs `nordlayerd` without systemd, as the `nordlayer`
user with the same capabilities its systemd unit grants, plus `microsocks`
(SOCKS5) and `tinyproxy` (HTTP) as `nobody`. Docker Desktop has no WireGuard
kernel module, so NordLayer falls back to its built-in user-space WireGuard. If
any of them dies, the container exits, so a dead tunnel never looks like a live
proxy.

## Building

```sh
scripts/build-app.sh --install   # build, sign (Developer ID), install to /Applications
scripts/release.sh 0.2.0         # notarize, GitHub release, bump the Homebrew cask
```
