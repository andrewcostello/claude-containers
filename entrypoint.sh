#!/bin/bash
set -e

# Fix ownership of .claude dir if mounted as a fresh volume (created by root)
if [ -d "$HOME/.claude" ] && [ ! -w "$HOME/.claude" ]; then
    echo "Fixing .claude directory permissions..."
    sudo chown -R "$(id -u):$(id -g)" "$HOME/.claude"
fi

# Make .gitconfig writable — the host copy is mounted read-only, but git
# needs to write to it (e.g., safe.directory for worktree mounts).
# Copy to a writable location and mark all directories safe (everything
# in the container is trusted project code).
if [ -f "$HOME/.gitconfig" ]; then
    cp "$HOME/.gitconfig" "$HOME/.gitconfig.local"
else
    touch "$HOME/.gitconfig.local"
fi
git config --file "$HOME/.gitconfig.local" --add safe.directory '*'
export GIT_CONFIG_GLOBAL="$HOME/.gitconfig.local"

# Fix ownership of directories Docker may have created as root
# (happens when bind-mounting a file into a non-existent parent dir)
for dir in "$HOME/.kube" "$HOME/.aws"; do
    if [ -d "$dir" ] && [ ! -w "$dir" ]; then
        sudo chown "$(id -u):$(id -g)" "$dir"
    fi
done

# Sync config from base project volume.
# ~/.claude-base is the base project config volume (read-only), containing
# auth credentials, settings, plugins, etc. from the main container.
# ~/.claude is this instance's config volume.
# - First run: clone everything from base so worktree starts fully configured
# - Subsequent runs: always refresh auth files so --login propagates immediately
BASE_DIR="$HOME/.claude-base"
if [ -d "$BASE_DIR" ] && [ -f "$BASE_DIR/.credentials.json" ]; then
    if [ ! -f "$HOME/.claude/.credentials.json" ]; then
        # First run — full clone from base
        echo "Seeding config from base project volume..."
        cp -a "$BASE_DIR"/. "$HOME/.claude/" 2>/dev/null || true
        # Clear session-specific state that shouldn't carry over
        rm -rf "$HOME/.claude/sessions" "$HOME/.claude/session-env" \
               "$HOME/.claude/history.jsonl" "$HOME/.claude/shell-snapshots" 2>/dev/null || true
    else
        # Subsequent runs — refresh auth credentials from base
        cp "$BASE_DIR/.credentials.json" "$HOME/.claude/.credentials.json" 2>/dev/null || true
        cp "$BASE_DIR/.claude.json" "$HOME/.claude/.claude.json" 2>/dev/null || true
    fi
fi

# Claude Code uses both ~/.claude/ (dir) and ~/.claude.json (file).
# The volume only covers ~/.claude/, so we persist .claude.json inside
# the volume and always symlink it. The symlink means writes go directly
# to the volume — no cleanup trap needed, survives Ctrl+C / kill.
STORED="$HOME/.claude/.claude.json"

if [ ! -f "$STORED" ] && [ -d "$HOME/.claude/backups" ]; then
    # First run — seed from backup if available
    backup=$(ls -t "$HOME/.claude/backups"/.claude.json.backup.* 2>/dev/null | head -1)
    if [ -n "$backup" ]; then
        cp "$backup" "$STORED"
    fi
fi

# Ensure the file exists so the symlink target is valid
touch "$STORED"
ln -sf "$STORED" "$HOME/.claude.json"

# Auto-install dependencies if missing (common with fresh worktrees)
if [ -f /workspace/package.json ] && [ ! -d /workspace/node_modules ]; then
    if [ -f /workspace/pnpm-lock.yaml ]; then
        echo "Installing dependencies (pnpm)..."
        (cd /workspace && pnpm install --frozen-lockfile 2>&1) || echo "Warning: pnpm install failed — Claude can retry"
    elif [ -f /workspace/yarn.lock ]; then
        echo "Installing dependencies (yarn)..."
        (cd /workspace && yarn install --frozen-lockfile 2>&1) || echo "Warning: yarn install failed — Claude can retry"
    elif [ -f /workspace/package-lock.json ]; then
        echo "Installing dependencies (npm)..."
        (cd /workspace && npm ci 2>&1) || echo "Warning: npm ci failed — Claude can retry"
    fi
fi

# Minikube shim — Tilt needs a `minikube` binary to discover the Docker daemon.
# The real minikube runs on the host; this shim returns the env vars passed in
# by the launcher (dynamically discovered at launch time).
if [ -n "${MINIKUBE_DOCKER_HOST:-}" ]; then
    cat > /tmp/minikube << SHIM
#!/bin/bash
case "\${*//-p minikube /}" in
    "docker-env"*)
        echo 'export DOCKER_TLS_VERIFY="1"'
        echo 'export DOCKER_HOST="${MINIKUBE_DOCKER_HOST}"'
        echo 'export DOCKER_CERT_PATH="${MINIKUBE_CERT_PATH}"'
        echo 'export MINIKUBE_ACTIVE_DOCKERD="minikube"' ;;
    version*) echo "minikube version: ${MINIKUBE_VERSION}" ;;
    ip*) echo "${MINIKUBE_IP}" ;;
    status*) echo "host: Running"; echo "kubelet: Running"; echo "apiserver: Running" ;;
esac
SHIM
    chmod +x /tmp/minikube
    export PATH="/tmp:$PATH"
fi

# Inject MCP server configs into settings.json when API keys are present
# This ensures Figma (and future MCPs) work automatically in all containers
SETTINGS="$HOME/.claude/settings.json"
if [ -n "${FIGMA_API_KEY:-}" ]; then
    # Ensure settings.json exists with valid JSON
    if [ ! -f "$SETTINGS" ] || [ ! -s "$SETTINGS" ]; then
        echo '{}' > "$SETTINGS"
    fi
    # Add Figma MCP server config if not already present
    if ! grep -q 'figma' "$SETTINGS" 2>/dev/null; then
        python3 -c "
import json, sys
with open('$SETTINGS') as f:
    settings = json.load(f)
settings.setdefault('mcpServers', {})['figma'] = {
    'command': 'npx',
    'args': ['-y', '@anthropic-ai/claude-code-figma-mcp@latest'],
    'env': {'FIGMA_API_KEY': '$FIGMA_API_KEY'}
}
with open('$SETTINGS', 'w') as f:
    json.dump(settings, f, indent=2)
" 2>/dev/null && echo "Figma MCP configured"
    fi
fi

# Project-colored banner
if [ -n "${CLAUDE_PROJECT:-}" ]; then
    hash_val=$(printf '%s' "$CLAUDE_PROJECT" | cksum | cut -d' ' -f1)
    color_code=$(( (hash_val % 6) + 31 ))
    instance_info=""
    if [ "$(hostname)" != "claude-${CLAUDE_PROJECT}" ]; then
        instance_info=" ($(hostname))"
    fi
    printf "\033[1;${color_code}m══════ %s%s ══════\033[0m\n" "$CLAUDE_PROJECT" "$instance_info"
fi

exec claude "$@"
