FROM registry.fedoraproject.org/fedora:43

LABEL org.opencontainers.image.source="https://github.com/linuxnow/dev-workstation"
LABEL org.opencontainers.image.description="Fedora 43 dev workstation with systemd + sshd"

# Enable full docs (like fedora-toolbox)
RUN rm -f /etc/rpm/macros.image-language-conf && \
    sed -i '/tsflags=nodocs/d' /etc/dnf/dnf.conf

# Full coreutils and locale support (like fedora-toolbox)
RUN dnf -y swap coreutils-single coreutils-full && \
    dnf -y swap glibc-minimal-langpack glibc-all-langpacks

# Install systemd first (required for PID 1)
RUN dnf install -y systemd openssh-server && \
    systemctl enable sshd

# RPM Fusion repos (free + nonfree)
RUN dnf install -y \
    https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-43.noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-43.noarch.rpm

# Xibo Players repo
RUN dnf install -y \
    https://dnf.xiboplayer.org/rpm/fedora/43/noarch/xiboplayer-release-43-1.fc43.noarch.rpm

# Toolbox packages (same as fedora-toolbox image)
RUN dnf install -y \
    bash-completion bc bzip2 cracklib-dicts diffutils \
    findutils flatpak-spawn fpaste gawk-all-langpacks \
    git glibc-gconv-extra gnupg2 gnupg2-smime gvfs-client \
    hostname iproute iputils keyutils krb5-libs less lsof \
    man-db man-pages mtr nano openssh-clients \
    passwd pigz procps-ng psmisc rsync shadow-utils sudo \
    tcpdump time traceroute tree unzip util-linux \
    vte-profile wget which whois words xz zip

# Base system tools (on top of toolbox)
RUN dnf install -y \
    curl jq tmux vim pinentry-tty \
    && dnf clean all

# Dev tools
RUN dnf install -y \
    nodejs npm gh ansible-core python3-pip \
    gcc gcc-c++ make cmake \
    && dnf clean all

# npm globals
RUN npm install -g pnpm@latest @anthropic-ai/claude-code

# Create dev user
RUN useradd -m -u 1000 -s /bin/bash -G wheel pau && \
    echo '%wheel ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/wheel && \
    chmod 440 /etc/sudoers.d/wheel

# SSH host keys will be generated on first boot by systemd
# User keys are injected by the setup playbook via volume mount

EXPOSE 22

CMD ["/sbin/init"]
