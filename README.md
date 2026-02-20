# dev-workstation

Fedora 43 dev workstation container image with systemd as PID 1.

## What's included

- **systemd + sshd** (enabled, PID 1)
- **RPM Fusion** free + nonfree repos
- **Xibo Players** repo
- **Dev tools**: nodejs, npm, pnpm, gh, ansible-core, gcc, cmake
- **CLI tools**: tmux, git, gnupg2, curl, wget, rsync, jq
- **npm globals**: pnpm, claude-code
- **User**: `pau` (uid 1000, wheel/sudo)

## Usage

```bash
podman pull ghcr.io/linuxnow/dev-workstation:43
```

Deployed as a rootless Quadlet on h1.superpantalles.com via:
```bash
ansible-playbook playbooks/services/install.yml -e service=dev_workstation
ansible-playbook playbooks/services/setup-dev-workstation.yml
```

## Image updates

Rebuilt automatically every Monday at 06:00 UTC via GitHub Actions, picking up:
- Fedora package updates (`dnf install` pulls latest)
- npm global updates (pnpm, claude-code)
- RPM Fusion updates

The Quadlet's `AutoUpdate=registry` pulls the latest image on the host.
