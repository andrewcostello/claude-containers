FROM golang:1.25-bookworm

# System dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    ca-certificates \
    tzdata \
    build-essential \
    python3 \
    python3-pip \
    python3-venv \
    jq \
    unzip \
    openssh-client \
    && rm -rf /var/lib/apt/lists/*

# Node.js 20 (matches host)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# golangci-lint
RUN curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh \
    | sh -s -- -b /usr/local/bin v2.9.0

# buf CLI
RUN ARCH=$(uname -m | sed 's/aarch64/aarch64/;s/x86_64/x86_64/') && \
    curl -sSL "https://github.com/bufbuild/buf/releases/latest/download/buf-Linux-${ARCH}" \
    -o /usr/local/bin/buf && chmod +x /usr/local/bin/buf

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Docker CLI + Compose plugin (for managing devcontainers / compose stacks)
RUN curl -fsSL https://download.docker.com/linux/debian/gpg \
    | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian bookworm stable" \
    > /etc/apt/sources.list.d/docker.list \
    && apt-get update && apt-get install -y --no-install-recommends docker-ce-cli docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user matching host UID (overridable at build time)
ARG HOST_UID=1000
ARG HOST_GID=1000
ARG DOCKER_GID=122
RUN groupadd -g ${HOST_GID} claude 2>/dev/null || true \
    && useradd -m -u ${HOST_UID} -g ${HOST_GID} -s /bin/bash claude \
    && (groupmod -g ${DOCKER_GID} docker 2>/dev/null || groupadd -g ${DOCKER_GID} docker 2>/dev/null || true) \
    && usermod -aG docker claude

# Passwordless sudo for fixing volume permissions on first run
RUN apt-get update && apt-get install -y --no-install-recommends sudo \
    && rm -rf /var/lib/apt/lists/* \
    && echo "claude ALL=(ALL) NOPASSWD: /bin/chown" >> /etc/sudoers.d/claude

# Pre-create .claude dir owned by claude user so volume mounts inherit ownership
RUN mkdir -p /home/claude/.claude && chown -R ${HOST_UID}:${HOST_GID} /home/claude/.claude

# Entrypoint that fixes volume ownership then execs claude
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

USER claude

# Claude Code (native installer)
ENV PATH="/home/claude/.local/bin:${PATH}"
RUN curl -fsSL https://claude.ai/install.sh | bash

WORKDIR /workspace

ENTRYPOINT ["entrypoint.sh"]
