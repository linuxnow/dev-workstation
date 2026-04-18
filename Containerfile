FROM registry.fedoraproject.org/fedora-toolbox:43

LABEL org.opencontainers.image.source="https://github.com/linuxnow/dev-workstation"
LABEL org.opencontainers.image.description="Fedora 43 dev workstation (toolbox base) with systemd + sshd + dev tooling"

# fedora-toolbox:43 already provides:
#   - full docs (macros.image-language-conf removed, tsflags=nodocs stripped)
#   - coreutils-full, glibc-all-langpacks
#   - bash-completion, bc, bzip2, diffutils, findutils, flatpak-spawn,
#     gawk-all-langpacks, git, glibc-gconv-extra, gnupg2, gnupg2-smime,
#     gvfs-client, hostname, iproute, iputils, keyutils, krb5-libs, less,
#     lsof, man-db, man-pages, mtr, nano, openssh-clients, passwd, pigz,
#     procps-ng, psmisc, rsync, shadow-utils, sudo, tcpdump, time,
#     traceroute, tree, unzip, util-linux, vte-profile, wget, which,
#     whois, words, xz, zip
# See: https://src.fedoraproject.org/container/fedora-toolbox
#
# What we add on top:
#   - systemd + openssh-server (toolbox runs via podman-exec; we run
#     as a systemd-PID-1 pod so Ansible can drive it like a VM)
#   - dev stack (nodejs, ansible, gh, claude-code, pnpm, pass, sops, …)

# systemd + sshd so the container can run as a persistent pod
RUN dnf install -y systemd openssh-server && \
    systemctl enable sshd && \
    dnf clean all

# RPM Fusion repos (free + nonfree)
RUN dnf install -y \
    https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-43.noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-43.noarch.rpm

# Xibo Players repo
RUN dnf install -y \
    https://dl.xiboplayer.org/rpm/fedora/43/noarch/xiboplayer-release-43-7.fc43.noarch.rpm

# Extra interactive shell tools not in toolbox base
RUN dnf install -y \
    curl jq tmux vim-enhanced pinentry-tty \
    && dnf clean all

# Dev tools
RUN dnf install -y \
    nodejs npm gh ansible-core python3-pip python3-pyyaml \
    git-filter-repo \
    gcc gcc-c++ make cmake \
    && dnf clean all

# Backup, test, and DB tooling
#
# - restic:     R2-backed backups of Podman volumes + Claude memory
#               (see playbooks/services/backup-{h1,local}.yml)
# - bats:       bash test framework (xiboplayer-chromium + xiboplayer-kiosk
#               test suites — the kiosk tests in tests/unit/ gate the
#               shellcheck.yml + test.yml GH Actions workflows added in
#               xibo-players/xiboplayer-kiosk#74)
# - ShellCheck: static shell-script analyser. Matches the -S error check
#               run by xiboplayer-kiosk's .github/workflows/shellcheck.yml
#               so maintainers can reproduce CI locally with `shellcheck
#               kiosk/*.sh` before pushing a PR.
# - sqlite:     CLI for inspecting knowledge.db and other SQLite files
#               (see xiboplayer-ai/docs/REBUILD.md verify steps)
# - qpdf:       encrypted-PDF page counting fallback
#               (xiboplayer-kiosk PDF provider patch, dormant)
# - awscli2:    R2 operations required by cleanup-artifacts.yml
# - pass:       Unix password store; ansible playbooks use
#               `lookup('pipe', 'pass show …')` for non-vault secrets
RUN dnf install -y \
    restic bats ShellCheck sqlite qpdf awscli2 pass \
    && dnf clean all

# sops — not in Fedora repos; install upstream RPM. Decrypts
# group_vars/all/vault.sops.yml so playbooks can run unattended
# (no YubiKey on dev-workstation).
RUN dnf install -y \
    https://github.com/getsops/sops/releases/download/v3.12.2/sops-3.12.2-1.x86_64.rpm \
    && dnf clean all

# xiboplayer-kiosk PR4 branding-asset generation
#
# - ImageMagick:  Plymouth + anaconda branding asset generation per the
#                 PR4 blueprint recipes (23 PNGs derived from
#                 kiosk/xiboplayer-kiosk-logo.png via `magick` one-
#                 liners — see project_xiboplayer_kiosk_pending_features
#                 memory).
#
# NOTE — explicitly NOT installing python3-gobject, gtk4, libadwaita,
# python3-pytest. The 0.5.0 first-boot wizard is a GTK4+libadwaita app
# whose useful test path is rendering it on a real display. The dev-
# workstation container is headless (no DISPLAY/Wayland), so the only
# things we could run here are import smoke checks — not worth the
# ~30 MB of extra image. Wizard testing happens on a laptop with a
# Wayland session, or on the test ISO booted in QEMU.
RUN dnf install -y \
    ImageMagick \
    && dnf clean all

# npm globals
RUN npm install -g pnpm@latest @anthropic-ai/claude-code

# Create dev user (toolbox image has no default user — it's expected to
# be run with --user at runtime; we bake a "pau" user because the pod
# runs as systemd-PID-1 and needs a fixed UID for volume-mounted home)
RUN useradd -m -u 1000 -s /bin/bash -G wheel pau && \
    echo '%wheel ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/wheel && \
    chmod 440 /etc/sudoers.d/wheel

# SSH host keys will be generated on first boot by systemd
# User keys are injected by the setup playbook via volume mount

EXPOSE 22

CMD ["/sbin/init"]
