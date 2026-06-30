# Dokploy Implementation Guide

Step-by-step instructions to deploy the Plex + *arr media stack on [Dokploy](https://dokploy.com). Complete each phase in order.

For architecture overview, security notes, and troubleshooting, see [README.md](README.md).

This guide assumes a **primary Dokploy** instance deploying to a **remote server** (e.g. a home server on Tailscale). Traefik domains are **not** used for this stack.

---

## Before you start

### Checklist

- [ ] Primary Dokploy installed and connected to the deploy target
- [ ] [Tailscale](https://tailscale.com/) running on the deploy host
- [ ] [cloudflared](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) installed on the deploy host
- [ ] A domain in Cloudflare (for the Plex tunnel only)
- [ ] PIA VPN subscription with username and password
- [ ] Plex account
- [ ] Enough disk space on a **single filesystem** for media + downloads (hardlinks require this)

### What you will configure

| Phase | Time estimate |
|-------|---------------|
| 1. Prepare the deploy server | 15 min |
| 2. Configure environment | 10 min |
| 3. Create Dokploy project | 10 min |
| 4. First deploy | 5–15 min |
| 5. Cloudflare Tunnel (Plex) | 10 min |
| 6. Verify VPN | 5 min |
| 7. Configure applications | 30–60 min |

---

## Phase 1: Prepare the deploy server

### Step 1.1 — Choose storage paths

Pick two absolute paths on the deploy host:

| Variable | Purpose | Example |
|----------|---------|---------|
| `MEDIA_ROOT` | Downloads + library | `/home/matt/PLEX/media` |
| `CONFIG_ROOT` | App settings and databases | `/home/matt/PLEX/config` |

Both paths must be on the host where containers run.

### Step 1.2 — Get your user ID

SSH into the deploy server and run:

```bash
id your_user
```

Note the `uid` and `gid` (usually `1000` / `1000`). You will use these as `PUID` and `PGID`.

### Step 1.3 — Create directories

```bash
export MEDIA_ROOT=/home/matt/PLEX/media    # change to your path
export CONFIG_ROOT=/home/matt/PLEX/config  # change to your path
export PUID=1000                           # change to your uid
export PGID=1000                           # change to your gid

mkdir -p ${MEDIA_ROOT}/torrents/{movies,tv,incomplete}
mkdir -p ${MEDIA_ROOT}/media/{movies,tv}
mkdir -p ${CONFIG_ROOT}/{plex,sonarr,radarr,prowlarr,seerr,qbittorrent,gluetun}

chown -R ${PUID}:${PGID} ${MEDIA_ROOT} ${CONFIG_ROOT}
```

### Step 1.4 — Get Tailscale IP

On the deploy host:

```bash
tailscale ip -4
```

Save this as `BIND_IP` — admin UIs will listen only on this address.

### Step 1.5 — Confirm VPN support

Gluetun needs TUN device access on the host:

```bash
ls -l /dev/net/tun
```

If the file exists, you are good. Docker must run with privileges that allow `NET_ADMIN`.

---

## Phase 2: Configure environment

### Step 2.1 — Copy the template

On your local machine or server, in this project directory:

```bash
cp .env.example .env
```

### Step 2.2 — Fill in every value

Edit `.env`:

```bash
# --- Identity / paths ---
PUID=1000
PGID=1000
TZ=America/New_York
MEDIA_ROOT=/home/matt/PLEX/media
CONFIG_ROOT=/home/matt/PLEX/config

# --- PIA VPN (Gluetun) ---
OPENVPN_USER=p1234567
OPENVPN_PASSWORD=your_pia_password
SERVER_REGIONS=Netherlands,CA Toronto,Switzerland
VPN_PORT_FORWARDING=on

# --- Network / access ---
BIND_IP=100.x.x.x
LAN_SUBNET=192.168.1.0/24,100.64.0.0/10
DOCKER_SUBNET=10.0.0.0/8

# --- Plex ---
PLEX_CLAIM=

# --- qBittorrent ---
WEBUI_PORT=8080

# --- Prowlarr ---
PROWLARR_PORT=9696
```

| Variable | What to enter |
|----------|---------------|
| `MEDIA_ROOT` / `CONFIG_ROOT` | Paths from Step 1.1 |
| `PUID` / `PGID` | Values from Step 1.2 |
| `TZ` | Your [timezone](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones) |
| `BIND_IP` | Tailscale IP from Step 1.4 |
| `OPENVPN_USER` / `OPENVPN_PASSWORD` | PIA credentials |
| `SERVER_REGIONS` | Comma-separated **non-US** PIA regions; compose sets `PORT_FORWARD_ONLY=on` |
| `LAN_SUBNET` | Your LAN CIDR **and** `100.64.0.0/10` (Tailscale), comma-separated |
| `DOCKER_SUBNET` | Leave as `10.0.0.0/8` unless Gluetun blocks inter-container traffic |
| `PLEX_CLAIM` | Leave empty for now — set in Phase 4 |
| `WEBUI_PORT` | Leave as `8080` unless you have a conflict |
| `PROWLARR_PORT` | Leave as `9696` unless you have a conflict |

> **Do not commit `.env`** — it contains secrets and is gitignored.

---

## Phase 3: Create the Dokploy project

### Step 3.1 — Create a project

1. Log in to your **primary** Dokploy instance.
2. Go to **Projects** → **Create Project**.
3. Name it (e.g. `media-stack`).
4. Select the **remote deploy target** (your Tailscale server).

### Step 3.2 — Add a Docker Compose service

1. Inside the project, click **Create Service** → **Docker Compose**.
2. Choose one of:
   - **Git repository** — connect this repo and set compose file path to `docker-compose.yml`
   - **Raw compose** — paste the contents of `docker-compose.yml`

### Step 3.3 — Set environment variables in Dokploy

1. Open the service → **Environment** tab.
2. Paste **every** variable from your `.env` file (same keys and values).
3. Save.

Dokploy injects these into Compose substitution (`${VAR}`). VPN credentials are only referenced in the Gluetun service block.

### Step 3.4 — Verify compose settings

- Compose file path: `docker-compose.yml`
- Deploy from the **full Git repository** (not raw compose paste only) so `qbittorrent-init/` is available on the deploy host
- Do **not** add `container_name` to any service (breaks Dokploy logs/metrics)
- The stack expects external network `dokploy-network` (Dokploy creates this on the deploy host)
- **Do not assign Domains** in Dokploy for any service in this stack

---

## Phase 4: First deploy

### Step 4.1 — Migrate Overseerr data (if upgrading)

If you have an existing Overseerr deployment, run on the deploy host **before** deploying:

```bash
export CONFIG_ROOT=/home/matt/PLEX/config   # change to your path

cp -a ${CONFIG_ROOT}/overseerr ${CONFIG_ROOT}/overseerr.backup-$(date +%Y%m%d)
cp -a ${CONFIG_ROOT}/overseerr ${CONFIG_ROOT}/seerr
chown -R 1000:1000 ${CONFIG_ROOT}/seerr
```

Seerr auto-migrates the Overseerr database on first startup. Skip this step for fresh installs — just ensure `${CONFIG_ROOT}/seerr` exists with correct permissions.

### Step 4.2 — Claim Plex (time-sensitive)

1. Open https://plex.tv/claim in your browser.
2. Copy the claim token.
3. Set `PLEX_CLAIM=<token>` in Dokploy Environment **immediately**.
4. Token expires in **4 minutes** — deploy right after setting it.

### Step 4.3 — Deploy

1. Click **Deploy** in Dokploy.
2. Watch the build/deploy logs.
3. Wait until all 7 containers are running:
   - `gluetun`
   - `qbittorrent`
   - `plex`
   - `sonarr`
   - `radarr`
   - `prowlarr`
   - `seerr`

### Step 4.4 — Confirm Gluetun is healthy

On the deploy host:

```bash
docker ps --filter "name=gluetun"
```

Status should be **healthy**.

### Step 4.5 — Confirm Tailscale port bindings

On the deploy host:

```bash
ss -tlnp | grep 100.
```

You should see ports **5055**, **8989**, **7878**, **9696**, and **8080** bound to your `BIND_IP`.

### Step 4.6 — Clear Plex claim (optional)

After Plex links to your account, remove `PLEX_CLAIM` from the environment and redeploy.

---

## Phase 5: Cloudflare Tunnel (Plex only)

Plex public access uses **cloudflared on the deploy host** — not a Docker container. The stack publishes Plex on `127.0.0.1:32400` for the host tunnel to forward.

### Step 5.1 — Confirm host cloudflared

On the deploy host:

```bash
systemctl status cloudflared
```

If not installed, follow [Cloudflare's Linux install guide](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/).

### Step 5.2 — Configure public hostname

In **Cloudflare Zero Trust** → your tunnel → **Public Hostname**:

| Field | Value |
|-------|-------|
| Subdomain | `plex` (or your choice) |
| Domain | `yourdomain.com` |
| Service type | HTTP |
| URL | `http://127.0.0.1:32400` |

> Use `127.0.0.1`, not `plex` — the Docker hostname is not resolvable from the host.

### Step 5.3 — Verify Plex is reachable locally

On the deploy host:

```bash
ss -tlnp | grep 32400
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:32400/web
```

Should show Plex listening on `127.0.0.1:32400` and return `200` or `301`.

### Step 5.4 — Configure Plex

1. Open Plex via `https://plex.yourdomain.com`.
2. **Settings → Network** → disable **Remote Access**.
3. **Settings → Network** → **Custom server access URLs**: `https://plex.yourdomain.com`.

---

## Phase 6: Verify VPN

### Step 6.1 — Check VPN IP

```bash
docker exec $(docker ps -q --filter "name=gluetun") wget -qO- https://api.ipify.org
```

The returned IP should **not** match your home/server public IP.

### Step 6.2 — Confirm port forwarding (optional)

```bash
docker logs $(docker ps -q --filter "name=gluetun") 2>&1 | grep -iE "port forward|forwarded port"
```

You should see a forwarded port assigned. If you see `API IP address not found`, update `SERVER_REGIONS` to regions known to support PIA forwarding (e.g. `Netherlands,CA Toronto,Switzerland`) and redeploy. Compose already sets `PORT_FORWARD_ONLY=on`.

---

## Phase 7: Configure applications

Access each service at `http://<BIND_IP>:<port>` from a device on your Tailscale network.

| Service | URL |
|---------|-----|
| Seerr | `http://100.x.x.x:5055` |
| Sonarr | `http://100.x.x.x:8989` |
| Radarr | `http://100.x.x.x:7878` |
| Prowlarr | `http://100.x.x.x:9696` |
| qBittorrent | `http://100.x.x.x:8080` |
| Plex | `https://plex.yourdomain.com` |

Configure in this order — later steps depend on earlier ones.

### Step 7.1 — qBittorrent

URL: `http://<BIND_IP>:8080`

The compose file mounts `qbittorrent-init/10-configure-paths.sh`, which on every start sets save path `/data/torrents`, incomplete path `/data/torrents/incomplete`, and enables localhost auth bypass for Gluetun.

1. Get the temporary password from logs:
   ```bash
   docker logs $(docker ps -q --filter "name=qbittorrent")
   ```
2. Log in as `admin` with the temporary password.
3. **Settings → Web UI** → change username and password.
4. **Settings → Downloads** → confirm default save path is `/data/torrents`.
5. **Settings → Connection** → confirm **UPnP** is disabled.
6. Click **Save**.

### Step 7.2 — Prowlarr

URL: `http://<BIND_IP>:9696`

1. **Settings → General** → set **Prowlarr Server URL** to `http://gluetun:9696`.
2. **Settings → General** → set authentication (Forms login recommended).
3. **Settings → Indexers → Indexer Proxies** → add **FlareSolverr**:
   - Host: `http://127.0.0.1:8191`
   - Tag: `flaresolverr`
4. **Indexers** → **Add Indexer** → add your torrent indexers. For Cloudflare-protected sites (e.g. **1337x**), apply the `flaresolverr` tag.
5. **Settings → Apps** → **Add Application**:
   - **Sonarr** — Prowlarr Server: `http://gluetun:9696`, Sonarr Server: `http://sonarr:8989`
   - **Radarr** — Prowlarr Server: `http://gluetun:9696`, Radarr Server: `http://radarr:7878`
6. Test each connection and save.

> FlareSolverr runs through the VPN alongside Prowlarr. Cloudflare-protected indexers like 1337x require the `flaresolverr` tag on the indexer.

### Step 7.3 — Sonarr

URL: `http://<BIND_IP>:8989`

1. **Settings → General** → note the **API Key**; enable authentication.
2. **Settings → Media Management** → enable **Use Hardlinks instead of Copy**.
3. **Settings → Media Management → Root Folders** → add `/data/media/tv`.
4. **Settings → Download Clients** → **Add** → qBittorrent:
   - Host: `gluetun`, Port: `8080`, Category: `tv`
5. Return to Prowlarr and complete Sonarr app sync.

### Step 7.4 — Radarr

URL: `http://<BIND_IP>:7878`

1. **Settings → General** → note the **API Key**; enable authentication.
2. **Settings → Media Management** → enable **Use Hardlinks instead of Copy**.
3. **Settings → Media Management → Root Folders** → add `/data/media/movies`.
4. **Settings → Download Clients** → **Add** → qBittorrent:
   - Host: `gluetun`, Port: `8080`, Category: `movies`
5. Return to Prowlarr and complete Radarr app sync.

### Step 7.5 — Plex

URL: `https://plex.yourdomain.com`

1. Complete Plex setup wizard (account linked via `PLEX_CLAIM`).
2. **Settings → Manage → Libraries** → add `/data/media/movies` and `/data/media/tv`.
3. Disable native Remote Access; use Cloudflare custom URL.

### Step 7.6 — Seerr

URL: `http://<BIND_IP>:5055`

1. Sign in with **Plex**.
2. **Settings → Services → Sonarr** — hostname `sonarr`, port `8989`.
3. **Settings → Services → Radarr** — hostname `radarr`, port `7878`.

If migrating from Overseerr, check container logs for migration success:

```bash
docker logs $(docker ps -q --filter "name=seerr") 2>&1 | tail -50
```

---

## End-to-end test

1. [ ] Open Seerr on Tailscale → request a movie.
2. [ ] Radarr shows the movie as wanted / starts searching.
3. [ ] qBittorrent receives a torrent and downloads over VPN.
4. [ ] Radarr imports to `/data/media/movies`.
5. [ ] Plex shows the new movie (via Cloudflare URL).
6. [ ] Repeat with a TV show via Sonarr.

---

## Post-implementation checklist

| Item | Done |
|------|------|
| Admin UIs reachable on Tailscale (`BIND_IP:port`) | ☐ |
| Plex reachable via Cloudflare Tunnel | ☐ |
| No Dokploy Traefik domains assigned | ☐ |
| Gluetun container healthy | ☐ |
| VPN IP differs from server IP | ☐ |
| qBittorrent password changed | ☐ |
| Sonarr/Radarr/Prowlarr authentication enabled | ☐ |
| Plex Remote Access disabled; custom URL set | ☐ |
| Seerr connected to Plex, Sonarr, Radarr | ☐ |
| `${CONFIG_ROOT}` backup scheduled | ☐ |

---

## Quick reference

### Internal Docker hostnames (container-to-container)

| From | To | Address |
|------|-----|---------|
| Sonarr / Radarr | qBittorrent | `gluetun:8080` |
| Sonarr / Radarr | Prowlarr | `gluetun:9696` |
| Prowlarr | Sonarr | `sonarr:8989` |
| Prowlarr | Radarr | `radarr:7878` |
| Seerr | Sonarr | `sonarr:8989` |
| Seerr | Radarr | `radarr:7878` |

### Tailscale access URLs

| Service | Port |
|---------|------|
| Seerr | 5055 |
| Sonarr | 8989 |
| Radarr | 7878 |
| Prowlarr | 9696 |
| qBittorrent (via gluetun) | 8080 |
| Prowlarr (via gluetun) | 9696 |

### Redeploy after changes

When you update `docker-compose.yml` or environment variables in Dokploy:

1. Save changes on the primary Dokploy instance.
2. Click **Deploy**.
3. Verify affected containers restarted cleanly.

---

## Related docs

- [README.md](README.md) — architecture, security, maintenance, troubleshooting
- [.env.example](.env.example) — environment variable template
- [Dokploy Docker Compose docs](https://docs.dokploy.com/docs/core/docker-compose/example)
- [Cloudflare Tunnel docs](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)
- [TRaSH Guides](https://trash-guides.info/) — quality profiles and folder naming
