# OpenClaw Proxmox VE LXC

Helper scripts for deploying [OpenClaw](https://github.com/openclaw/openclaw) in a Proxmox VE LXC container, built for the [community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE) framework.

## What It Does

Creates an unprivileged Debian 13 LXC container with:

- **OpenClaw** installed natively via npm (gateway on `127.0.0.1:18789`)
- **Docker Engine** for OpenClaw's sandbox execution mode
- **Nginx** reverse proxy with TLS termination (port 443) and WebSocket support
- **Self-signed TLS certificate** (replaceable with Let's Encrypt)
- **Systemd services** for OpenClaw and Docker

## Container Defaults

| Resource | Value |
|----------|-------|
| CPU | 2 cores |
| RAM | 4096 MB |
| Disk | 16 GB |
| OS | Debian 13 (Trixie) |
| Type | Unprivileged (nesting + keyctl enabled) |

All defaults are adjustable during the interactive setup wizard.

## Quick Start

Run on a Proxmox VE host:

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/ludicrypt/openclaw-proxmox-lxc/main/ct/openclaw.sh)"
```

After the container is created:

```bash
# SSH into the container, then:
openclaw onboard
```

The `onboard` command walks you through choosing an AI model and configuring authentication.

Access the web interface at `https://<container-ip>`.

## Updating

Re-run the `ct/openclaw.sh` script and select the update option. This will:

- Update OpenClaw via `npm update -g openclaw`
- Update Docker Engine packages
- Restart the OpenClaw and Nginx services

## TLS Certificate

The installer generates a self-signed certificate. To replace it with Let's Encrypt:

```bash
apt install certbot python3-certbot-nginx
certbot --nginx -d your.domain.com
```

## Architecture

OpenClaw runs natively (not inside Docker) to avoid Docker-in-Docker-in-LXC complexity. Docker is installed separately and reserved for OpenClaw's sandbox functionality. Nginx sits in front as a reverse proxy, handling TLS and WebSocket upgrades.

```
Internet → :443 (Nginx/TLS) → :18789 (OpenClaw gateway) → Docker (sandbox)
```

## File Structure

```
ct/openclaw.sh              # Runs on PVE host — container defaults + update logic
install/openclaw-install.sh  # Runs inside LXC — full installation sequence
```

## License

[MIT](LICENSE)
