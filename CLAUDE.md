# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

Proxmox VE LXC helper scripts for deploying OpenClaw, following the [community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE) conventions. These scripts automate creating and configuring an unprivileged LXC container with OpenClaw installed natively via npm, Docker for sandbox mode, and Nginx as a TLS reverse proxy.

## Architecture

Two bash scripts, each running in a different context:

- **`ct/openclaw.sh`** -- Runs on the **Proxmox host**. Sources `build.func` from the community-scripts repo, declares container defaults (CPU, RAM, disk, OS), and provides the `update_script()` function for in-place updates. The build framework handles container creation, LXC feature flags (`nesting=1,keyctl=1` for Docker in unprivileged containers), and the interactive setup wizard.

- **`install/openclaw-install.sh`** -- Runs **inside the LXC** during creation. Sources helper functions via `$FUNCTIONS_FILE_PATH`, then installs: system deps, Node.js 22 (NodeSource), Docker Engine (get.docker.com), OpenClaw (npm global), a systemd service unit, a self-signed TLS cert, and Nginx reverse proxy config. OpenClaw gateway binds to `127.0.0.1:18789`; Nginx terminates TLS on port 443 and proxies to it with WebSocket support.

## Community-Scripts Conventions

These patterns must be preserved when editing the scripts:

### Host script (`ct/*.sh`)
- Source `build.func` via curl on line 2
- Declare `var_*` variables with `${var_name:-default}` syntax
- Call sequence: `header_info` → `variables` → `color` → `catch_errors`
- Define `update_script()` before calling `start` → `build_container` → `description`
- Use `$STD` prefix to suppress command output
- Use `msg_info`/`msg_ok`/`msg_error` for status messages
- Color variables: `${GN}`, `${YW}`, `${BGN}`, `${CL}`, `${CREATING}`, `${INFO}`, `${TAB}`, `${GATEWAY}`

### Install script (`install/*-install.sh`)
- Source functions: `source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"`
- Preamble: `color` → `verb_ip6` → `catch_errors` → `setting_up_container` → `network_check` → `update_os`
- Wrap every install step in `msg_info "..."`/`msg_ok "..."` pairs
- End with: `motd_ssh` → `customize` → cleanup

## Key Design Decisions

- **Install script URL patch**: The community-scripts `build_container()` function hardcodes fetching install scripts from `community-scripts/ProxmoxVE/main/install/`. Since this is a standalone repo, `ct/openclaw.sh` patches the function after sourcing `build.func` using `declare -f` + `sed` + `eval` to redirect the install URL to this repo. If `build.func` upstream changes the install URL pattern, this patch may break.
- OpenClaw is installed **natively via npm**, not inside Docker. Docker is only present for OpenClaw's sandbox execution feature. This avoids Docker-in-Docker-in-LXC complexity.
- The `docker` tag in `var_tags` signals the build framework to enable `nesting=1,keyctl=1` LXC features automatically.
- Nginx uses `proxy_read_timeout 86400s` (24h) because OpenClaw maintains long-lived WebSocket connections.
- The systemd service file lives at `/usr/lib/systemd/system/openclaw.service` -- the update script checks for this path to verify installation exists.

## Testing

These scripts cannot be unit-tested locally; they must be validated on a Proxmox VE host:

1. Run `bash -c "$(wget -qLO - https://raw.githubusercontent.com/<repo>/main/ct/openclaw.sh)"` on PVE
2. SSH into container: `docker run hello-world` (Docker works)
3. `systemctl status openclaw` (service running)
4. `curl -k https://localhost` (Nginx proxying to OpenClaw)
5. Re-run ct script, select update (update path works)

## Linting

```
shellcheck ct/openclaw.sh install/openclaw-install.sh
```

Note: ShellCheck will flag the dynamic `source` lines and `$STD` usage -- these are intentional community-scripts patterns. Use `# shellcheck disable=` directives if integrating ShellCheck into CI.
