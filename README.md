# nord-docker-proxy

Reach what's behind your NordLayer gateway **without putting your whole Mac on
the VPN.** NordLayer's Linux client runs in a Docker container and is exposed to
your Mac only as a password-protected SOCKS5 proxy on `127.0.0.1`. Only traffic
you send to the proxy uses the VPN, and only to the ports you allow. Everything
else on your Mac keeps its normal connection and speed.

Typical use: a database or service that is IP-allowlisted to your NordLayer
gateway, reached from scripts or tools on your Mac.

> Unofficial. Not affiliated with or endorsed by Nord Security / NordLayer.

## Install

```sh
brew install --cask taylorbird/nord-docker-proxy/nord-docker-proxy
nord-docker-proxy setup
```

Needs Docker Desktop (running) and a NordLayer account that can use SSO
(Google, Okta, Entra ID, OneLogin or JumpCloud). macOS 15+ (it uses the system `jq`), Apple silicon.

`setup` asks for your NordLayer organization ID and the destination ports to
allow, logs you in, and lets you pick a gateway. The menu bar app,
**Nord Docker Proxy**, then shows status and starts/stops everything; its icon
is green only when healthy.

## Use

| | |
|---|---|
| `nord-docker-proxy up [--hours N]` | start; reconnects if still logged in; optional auto-stop |
| `nord-docker-proxy down` | stop and remove the container: nothing reaches the VPN |
| `nord-docker-proxy status [--json]` | container / login / VPN exit / firewall / proxy |
| `nord-docker-proxy login` / `logout` | SSO login (below) / end the session and delete the saved login |
| `nord-docker-proxy connect` / `disconnect` | VPN only; the container stays up |
| `nord-docker-proxy gateways` | gateways your account can use |
| `nord-docker-proxy proxy-env` | `export` lines for scripts |
| `nord-docker-proxy rebuild` | rebuild the image (after updating the pinned package) |

Healthy means: the container exits at the gateway's address, the proxy
firewall is loaded, and the proxy answers an authenticated handshake.

## Configuration

Every setting is declared in [`compose.yaml`](compose.yaml). Your values live
in `~/.config/nord-docker-proxy/config.env` (written by `setup`, compose
env-file format):

| Setting | |
|---|---|
| `NDP_ORG` | NordLayer organization ID (required) |
| `NDP_GATEWAY` | gateway ID to connect to (required; see `gateways`) |
| `NDP_ALLOWED_PORTS` | destination ports the proxy may reach, e.g. `27017` or `5432,6379`, or `any` (required) |
| `NDP_ACCOUNT` | the only NordLayer email accepted at login (optional) |
| `NDP_MAX_HOURS` | auto-stop after N hours of uptime; `0` = never |
| `NDP_PROXY_PORT` | local proxy port (default `1080`) |
| `NDP_STATE_VOLUME` | Docker volume holding the login (default `nord-docker-proxy-state`) |

## Pointing things at the proxy

Load the credentials without printing them:

```sh
eval "$(nord-docker-proxy proxy-env)"   # NDP_PROXY_{HOST,PORT,USER,PASS,URL}
```

MongoDB Node driver (with the `socks` package installed next to `mongodb`):

```js
new MongoClient(uri, {
  proxyHost: process.env.NDP_PROXY_HOST, proxyPort: Number(process.env.NDP_PROXY_PORT),
  proxyUsername: process.env.NDP_PROXY_USER, proxyPassword: process.env.NDP_PROXY_PASS,
})
```

Anything that speaks SOCKS5 with a username/password works the same way
(`$NDP_PROXY_URL` is a `socks5h://` URL).

## Login

NordLayer's SSO ends by sending the browser to `nordlayer://auth?exchange_token=…`.
On a Mac that link belongs to the NordLayer app (or nothing), so the container
never sees it. `nord-docker-proxy login` picks your SSO method, opens the
sign-in page, and watches the clipboard: on the success page,
**right-click "Continue" → Copy Link** and it finishes by itself.

Logins last up to your organization's session timeout (NordLayer Control Panel
→ Settings → Security configurations). Clipboard managers and Universal
Clipboard may keep a copy of the link; it is used within about a second, but
if that worries you, exclude your browser from clipboard history or turn off
Handoff while logging in.

## Security model

- **Proxy password**, generated on first use into your login Keychain.
- **Proxy firewall** (nftables, inside the container, for the proxy's traffic
  only): new connections leave through the VPN tunnel or not at all, to
  `NDP_ALLOWED_PORTS` plus DNS. With the VPN down, the proxy can reach nothing.
  NordLayer's own kill switch stays **off** in the container: with it on,
  NordLayer drops every inbound connection on the container's interface,
  which is how your Mac reaches the proxy.
- **Loopback only**: the proxy is published on `127.0.0.1`.
- **Login check**: after login, the account must be in `NDP_ORG` (and be
  `NDP_ACCOUNT` when set), or it is logged out and the saved login deleted.
  This stops another app from slipping its own login link onto your clipboard.
  The token reaches the container over stdin, never as a process argument.
- **Pinned supply chain**: base image by digest, NordLayer `.deb` by sha256
  ([`docker/Dockerfile`](docker/Dockerfile)). A new NordLayer release fails the
  build until the hash is updated; `up` only builds when the image is missing.
- **Signed app, self-checking**: the CLI ships inside the signed app, which
  verifies its own signature and publisher before running it.
- **What it can't protect against**: anything with access to Docker on your
  Mac can read the saved login and the proxy password. Keep the tunnel down
  when you don't need it, and `logout` when you're done for a while.

## How it works

`docker/entrypoint.sh` runs `nordlayerd` without systemd, as the `nordlayer`
user with the same capabilities its systemd unit grants, plus `microsocks` as
`nobody`. Docker Desktop has no WireGuard kernel module, so NordLayer falls
back to its built-in user-space WireGuard. If either process dies, the
container exits, so a dead tunnel never looks like a live proxy.

## Building

```sh
scripts/build-app.sh --install   # build, sign (Developer ID), install to /Applications
scripts/release.sh 0.1.1         # notarize, GitHub release, bump the Homebrew cask
```
