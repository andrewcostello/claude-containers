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
    iproute2 \
    lsof \
    procps \
    psmisc \
    && rm -rf /var/lib/apt/lists/*

# Node.js 20 (matches host) + corepack for pnpm/yarn support
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && corepack enable

# golangci-lint
RUN curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh \
    | sh -s -- -b /usr/local/bin v2.9.0

# buf CLI
RUN ARCH=$(uname -m | sed 's/aarch64/aarch64/;s/x86_64/x86_64/') && \
    curl -sSL "https://github.com/bufbuild/buf/releases/latest/download/buf-Linux-${ARCH}" \
    -o /usr/local/bin/buf && chmod +x /usr/local/bin/buf

# protoc + gRPC-Web plugins (for proto code generation)
# Installs protoc-gen-js and protoc-gen-grpc-web on PATH by exact name
RUN apt-get update && apt-get install -y --no-install-recommends protobuf-compiler \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g protoc-gen-js protoc-gen-grpc-web

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

# AWS CLI v2 (arch-aware: x86_64 on Intel, aarch64 on Apple Silicon)
RUN ARCH=$(uname -m) && \
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${ARCH}.zip" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/aws /tmp/awscliv2.zip

# Gemini CLI (for multi-model reviews)
RUN npm install -g @google/gemini-cli

# OpenAI Codex CLI (for multi-model reviews)
RUN npm install -g @openai/codex

# kubectl (arch-aware: amd64 on Intel, arm64 on Apple Silicon)
RUN ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') && \
    curl -fsSL "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH}/kubectl" \
    -o /usr/local/bin/kubectl && chmod +x /usr/local/bin/kubectl

# Tilt (local Kubernetes dev)
RUN curl -fsSL https://raw.githubusercontent.com/tilt-dev/tilt/master/scripts/install.sh | bash

# Playwright browser dependencies (Chromium + Firefox headless testing)
# Uses Playwright's own dependency installer to stay in sync with browser requirements
RUN npx -y playwright install-deps chromium firefox

COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

USER claude

# Pre-install Playwright browsers (runtime cache volume keeps them across containers)
RUN npx -y playwright install chromium firefox

# Project-colored shell prompt (uses CLAUDE_PROJECT env var set at runtime)
RUN echo 'if [ -n "${CLAUDE_PROJECT:-}" ]; then' >> /home/claude/.bashrc \
    && echo '    _hash=$(printf "%s" "$CLAUDE_PROJECT" | cksum | cut -d" " -f1)' >> /home/claude/.bashrc \
    && echo '    _color=$(( (_hash % 6) + 31 ))' >> /home/claude/.bashrc \
    && echo '    PS1="\\[\\033[1;${_color}m\\][${CLAUDE_PROJECT}]\\[\\033[0m\\] \\w\\$ "' >> /home/claude/.bashrc \
    && echo '    unset _hash _color' >> /home/claude/.bashrc \
    && echo 'fi' >> /home/claude/.bashrc

# Claude Code (native installer)
ENV PATH="/home/claude/.local/bin:${PATH}"
RUN curl -fsSL https://claude.ai/install.sh | bash

WORKDIR /workspace

ENTRYPOINT ["entrypoint.sh"]
