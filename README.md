# Posterizarr – Proxmox Helper Script

Deploys [Posterizarr](https://github.com/fscorrupt/Posterizarr) (automated poster maker for Plex/Jellyfin/Emby) as an LXC container on Proxmox VE, following the same pattern used by [community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE).

---

## Container Defaults

| Setting     | Value       |
|-------------|-------------|
| OS          | Debian 12   |
| Disk        | 8 GB        |
| CPU         | 2 cores     |
| RAM         | 2048 MB     |
| Network     | DHCP        |
| Privileged  | No (unprivileged) |
| Web UI Port | 8000        |

---

## How to Use

### Option A — Host scripts on your own GitHub fork (recommended)

1. Fork or push this repo to your GitHub account.
2. SSH into your Proxmox host.
3. Run:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/ct/posterizarr.sh)"
```

The script will:
- Present the interactive mode menu (Default / Advanced / etc.)
- Create the LXC container
- Automatically run `install/posterizarr-install.sh` inside the container
- Print the Web UI URL when done

### Option B — Run locally from the Proxmox host

```bash
# Copy both files to your Proxmox host
scp ct/posterizarr.sh root@proxmox:/root/
scp install/posterizarr-install.sh root@proxmox:/root/

# On the Proxmox host, edit ct/posterizarr.sh and change the build.func source URL
# to point to the official community-scripts, OR host your own.
# Then run:
bash /root/posterizarr.sh
```

### Option C — Use alongside the official community-scripts framework

If you already have community-scripts set up on your Proxmox host, drop the files into the correct locations:
- `ct/posterizarr.sh` → `/usr/local/community-scripts/ct/posterizarr.sh`
- `install/posterizarr-install.sh` → `/usr/local/community-scripts/install/posterizarr-install.sh`

---

## File Structure

```
.
├── ct/
│   └── posterizarr.sh          # Runs on Proxmox HOST — creates the LXC container
└── install/
    └── posterizarr-install.sh  # Runs INSIDE the container — installs Posterizarr
```

This mirrors the exact layout of community-scripts/ProxmoxVE.

---

## What Gets Installed (inside the container)

| Component              | Notes                                      |
|------------------------|--------------------------------------------|
| PowerShell 7.x         | Required by Posterizarr.ps1               |
| Node.js 20.x           | Required for Web UI frontend               |
| Python 3 + uvicorn     | Required for Web UI backend (port 8000)   |
| ImageMagick 7.x        | Required for image processing              |
| FanartTvAPI PS Module  | Required PowerShell module                 |
| Posterizarr (latest)   | Installed to /opt/posterizarr             |
| systemd service        | posterizarr-backend (auto-start)          |

### Directories created

| Path              | Purpose                        |
|-------------------|--------------------------------|
| `/config`         | config.json (edit this!)       |
| `/assets`         | Output posters/assets          |
| `/assetsbackup`   | Asset backups                  |
| `/manualassets`   | Manual override assets         |

---

## After Installation

1. **Access Web UI:** `http://<container-ip>:8000`
2. **Edit config:** `/config/config.json` — add your TMDB, Fanart, TVDB API keys and media server details
3. **Test run:**
   ```bash
   pwsh /opt/posterizarr/Posterizarr.ps1 -Testing
   ```

### API Keys Required

- **TMDB Read Access Token** — https://www.themoviedb.org/settings/api *(use the long one)*
- **Fanart Personal API Key** — https://fanart.tv/get-an-api-key
- **TVDB Project API Key** — https://thetvdb.com/api-information/signup *(do NOT use Legacy Key)*

---

## Updating

Re-run the CT script from your Proxmox host and choose "Update" when prompted:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/ct/posterizarr.sh)"
```

The update function will:
- Compare current vs. latest GitHub release tag
- Stop the service, replace `/opt/posterizarr`, rebuild the frontend, restart the service

---

## Viewing Logs

```bash
# Inside the container
journalctl -u posterizarr-backend -f

# Service status
systemctl status posterizarr-backend
```
