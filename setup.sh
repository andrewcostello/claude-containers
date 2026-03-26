#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== claude-containers setup ==="
echo ""

# 1. Check prerequisites
echo "Checking prerequisites..."
for cmd in docker git; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: $cmd is required but not installed." >&2
        exit 1
    fi
done
echo "  docker: $(docker --version | head -1)"
echo "  git: $(git --version)"

# Verify docker is running
if ! docker info &>/dev/null; then
    echo "Error: Docker daemon is not running." >&2
    exit 1
fi

# 2. Create config.sh if it doesn't exist
if [[ ! -f "$SCRIPT_DIR/config.sh" ]]; then
    echo ""
    echo "Creating config.sh from template..."
    cp "$SCRIPT_DIR/config.example.sh" "$SCRIPT_DIR/config.sh"
    echo "  Edit $SCRIPT_DIR/config.sh to match your project layout."
    echo "  Then re-run this script."
    exit 0
fi

source "$SCRIPT_DIR/config.sh"

# 3. Validate config
echo ""
echo "Validating config..."
if [[ ! -d "$PROJECTS_DIR" ]]; then
    echo "Error: PROJECTS_DIR=$PROJECTS_DIR does not exist." >&2
    exit 1
fi
echo "  PROJECTS_DIR: $PROJECTS_DIR"

for key in "${!PROJECTS[@]}"; do
    dir="$PROJECTS_DIR/${PROJECTS[$key]}"
    if [[ -d "$dir" ]]; then
        echo "  $key -> ${PROJECTS[$key]} (found)"
    else
        echo "  $key -> ${PROJECTS[$key]} (NOT FOUND - clone the repo first)"
    fi
done

# 4. Build the Docker image
echo ""
echo "Building Docker image..."
docker build \
    --build-arg HOST_UID="$(id -u)" \
    --build-arg HOST_GID="$(id -g)" \
    --build-arg DOCKER_GID="$(getent group docker | cut -d: -f3)" \
    -t claude-dev \
    "$SCRIPT_DIR"

# 5. Symlink to PATH
echo ""
BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"
ln -sf "$SCRIPT_DIR/claude-in-container" "$BIN_DIR/claude-in-container"
echo "Symlinked claude-in-container to $BIN_DIR/"

if ! echo "$PATH" | grep -q "$BIN_DIR"; then
    echo ""
    echo "NOTE: $BIN_DIR is not in your PATH. Add it:"
    echo "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc"
fi

# 6. GitHub CLI token (optional)
echo ""
if command -v gh &>/dev/null && gh auth status &>/dev/null; then
    mkdir -p "$HOME/.config/gh"
    gh auth token > "$HOME/.config/gh/token"
    chmod 600 "$HOME/.config/gh/token"
    echo "GitHub CLI token saved for container use."
else
    echo "GitHub CLI not authenticated. Containers won't have gh access."
    echo "  Run: gh auth login && gh auth token > ~/.config/gh/token"
fi

# 7. Claude roles (optional)
echo ""
if [[ -n "${ROLES_DIR:-}" && ! -d "$ROLES_DIR" ]]; then
    echo "Cloning shared Claude roles..."
    git clone https://github.com/andrewcostello/claude-roles.git "$ROLES_DIR"
elif [[ -n "${ROLES_DIR:-}" && -d "$ROLES_DIR" ]]; then
    echo "Claude roles already cloned at $ROLES_DIR"
else
    echo "No ROLES_DIR configured, skipping roles."
fi

# 8. Done
echo ""
echo "=== Setup complete ==="
echo ""
echo "Next steps:"
echo "  1. Log in to Claude for each project:"
echo "     claude-in-container --login evenplay"
echo "     claude-in-container --login rr"
echo ""
echo "  2. Start using Claude:"
echo "     claude-in-container evenplay"
echo "     claude-in-container --worktree evenplay smg-1234"
echo ""
