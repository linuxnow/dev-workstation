FROM registry.fedoraproject.org/fedora-toolbox:44

LABEL org.opencontainers.image.source="https://github.com/linuxnow/dev-workstation"
LABEL org.opencontainers.image.description="Fedora 44 dev workstation (toolbox base) with systemd + sshd + dev tooling"

# fedora-toolbox:44 already provides:
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
    https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-44.noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-44.noarch.rpm

# Xibo Players repo — TODO: re-enable when fc44 build is available.
# As of 2026-05-01, dl.xiboplayer.org/rpm/fedora/44/ returns 404. The
# repo is informational only inside dev-workstation (we don't install
# any xiboplayer-* RPMs here — the player itself runs on physical
# kiosk hardware). Adding the repo lets `dnf search xiboplayer-*`
# work from inside the pod, but isn't load-bearing for any other
# step in this Containerfile.
# RUN dnf install -y \
#     https://dl.xiboplayer.org/rpm/fedora/44/noarch/xiboplayer-release-44-1.fc44.noarch.rpm

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

# Rust toolchain + arexibo (xibo-players/arexibo) build deps
#
# arexibo is a Rust/Qt6 Pi5 signage player that the overnight-audit
# 2026-04-21 CI gap revealed was never being built/tested in CI.
# Baked in here so dev-workstation can `cargo build / test / clippy`
# the fork branches without per-run dnf-install friction.
#
# Fedora package names mapped from arexibo's deb.yml extra-build-deps:
#   cargo              → rust + cargo
#   cmake              → already installed above
#   g++                → gcc-c++ (already)
#   libdbus-1-dev      → dbus-devel
#   libzmq3-dev        → zeromq-devel
#   qt6-webengine-dev  → qt6-qtwebengine-devel (+ pulls qt6-qtbase-devel)
#   libudev-dev        → systemd-devel (libudev is part of systemd)
#   pkg-config         → pkgconf-pkg-config
RUN dnf install -y \
    rust cargo clippy rustfmt \
    dbus-devel zeromq-devel \
    qt6-qtwebengine-devel \
    systemd-devel \
    pkgconf-pkg-config \
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

# Kubernetes tooling — laptop-replacement role for the dev-workstation
# pod on h2 (zerosignage/platform k8s/dev-workstation). Without these
# the operator has to ssh to the h2 host + sudo k3s kubectl for every
# cluster operation; with them, kubectl runs locally inside the pod
# against ~/.kube/config (mounted from the home PVC).
#
# - kubectl: official Kubernetes CLI.
# - helm:    pre-render charts before checkin per
#            reference_k8s_pre_render_helm_pattern.md (cilium, velero,
#            sops-secrets-operator etc.).
#
# Both come from pkgs.k8s.io — the official Kubernetes-project RPM
# repo (signed releases, GPG-checked at install time via gpgcheck=1
# + the published gpgkey URL).
#
# k9s (interactive cluster TUI) — pinned version + sha256 verified
# (vs. an unpinned `curl|tar -xz` to /usr/local/bin which would fetch
# `latest` with no integrity check). To bump:
#   1. https://github.com/derailed/k9s/releases — note the new tag
#   2. Download checksums.sha256 from the release; record the
#      k9s_Linux_amd64.tar.gz hash
#   3. Update K9S_VERSION + K9S_SHA256 ARGs below in lockstep
RUN tee /etc/yum.repos.d/kubernetes.repo > /dev/null <<'EOF'
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.32/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.32/rpm/repodata/repomd.xml.key
EOF
RUN dnf install -y kubectl helm && dnf clean all
ARG K9S_VERSION=v0.50.18
ARG K9S_SHA256=0b697ed4aa80997f7de4deeed6f1fba73df191b28bf691b1f28d2f45fa2a9e9b
RUN curl -sSLo /tmp/k9s.tar.gz \
        "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_amd64.tar.gz" && \
    echo "${K9S_SHA256}  /tmp/k9s.tar.gz" | sha256sum -c - && \
    tar -xzf /tmp/k9s.tar.gz -C /usr/local/bin k9s && \
    rm /tmp/k9s.tar.gz

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
