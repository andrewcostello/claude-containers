# claude-containers

Run Claude Code in isolated Docker containers per project. Each project gets its own Claude account/login while sharing host credentials (git, gh, SSH, AWS) read-only.

## Features

- **Isolated Claude logins** — separate accounts per project (personal vs professional)
- **Filesystem isolation** — containers can only access their own project
- **Per-worktree sessions** — concurrent agents on the same project don't conflict
- **Shared host credentials** — git, SSH, GitHub CLI, AWS, gcloud mounted read-only
- **Git worktree support** — spin up multiple Claude agents on the same project
- **Project-colored UI** — colored banners and shell prompts per project
- **Auto-dependency install** — npm/yarn/pnpm deps installed on worktree start
- **Kubernetes/Tilt support** — `--host-network` for local k8s development with minikube
- **Playwright browsers** — pre-installed Chromium and Firefox for headless testing
- **Figma MCP** — auto-configured when `FIGMA_API_KEY` is set in secrets.env
- **Shared caches** — npm, go, pip, and Playwright caches persist across containers
- **Resource limits** — configurable memory and CPU caps per container
- **Lifecycle commands** — `--stop` and `--prune` for clean worktree teardown

## Setup

```bash
git clone https://github.com/andrewcostello/claude-containers.git ~/Project/claude-containers
cd ~/Project/claude-containers
cp config.example.sh config.sh   # Edit this for your machine
./setup.sh
```

### Prerequisites

- Docker
- Git
- Claude Code subscription

### Configuration

Edit `config.sh` (gitignored) to define your projects:

```bash
PROJECTS_DIR="$HOME/Project"

declare -A PROJECTS=(
    [myapp]="myapp-repo"
    [backend]="backend-mono"
)

ROLES_DIR="$PROJECTS_DIR/claude-roles"  # or "" to disable
FORECAST_BIN=""                          # or path to forecast binary

# Resource limits (optional — these are the defaults)
# CONTAINER_MEMORY="8g"
# CONTAINER_CPUS="4"

# Docker socket: off by default, enable globally or per-project
# MOUNT_DOCKER_SOCKET="false"
# DOCKER_PROJECTS=("myapp")
```

### Secrets

Create `secrets.env` (gitignored) for API tokens injected into all containers:

```bash
JIRA_API_TOKEN=your_token
CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-...   # from --login setup-token
FIGMA_API_KEY=figd_...                      # enables Figma MCP automatically
```

## Usage

### Basic commands

```bash
# First-time auth — generates an OAuth token, add it to secrets.env
claude-in-container --login myapp

# Start Claude in a project
claude-in-container myapp

# Start with a prompt
claude-in-container myapp "fix the login bug"

# Open a bash shell (gets project-colored PS1 prompt)
claude-in-container --shell myapp

# List running containers (color-coded by project)
claude-in-container --list

# Rebuild the Docker image
claude-in-container --build
```

### Modifier flags

Modifier flags go before the command or project name and can be combined:

```bash
# Mount Docker socket (for devcontainers / compose)
claude-in-container --docker myapp

# Use host network (for Tilt, k8s port-forwards, minikube)
claude-in-container --host-network myapp

# Disable network access entirely
claude-in-container --offline myapp

# Combine flags
claude-in-container --docker --host-network --worktree myapp feature-x
```

| Flag | Effect |
|------|--------|
| `--docker` | Mounts Docker socket + Docker config |
| `--host-network` | Uses host network, mounts kube/minikube config, creates minikube shim (Linux/Windows). Implies `--docker`. **macOS:** requires [OrbStack](https://orbstack.dev) — use its built-in Kubernetes instead of minikube (no shim needed). |
| `--offline` | Sets `--network none` on the container |

### Worktrees — multiple agents on one project

Use `--worktree` to create isolated git worktrees, each with its own container and config volume:

```bash
# Create and start (branches from origin/main)
claude-in-container --worktree myapp auth-refactor
claude-in-container --worktree myapp fix-payments

# Resume an existing worktree (idempotent — reuses if it exists)
claude-in-container --worktree myapp auth-refactor

# Stop a worktree and clean everything up (container, directory, branch, volume)
claude-in-container --stop myapp auth-refactor

# Interactively prune all stale worktrees for a project
claude-in-container --prune myapp
```

Each worktree gets:
- Its own directory: `~/Project/<repo>-wt-<name>`
- Its own config volume: `claude-config-<project>-<name>`
- Auth seeded from the base project volume (no re-login needed)
- Dependencies auto-installed if `node_modules` is missing

### Kubernetes / Tilt with minikube

> **macOS:** Use [OrbStack](https://orbstack.dev) instead of Docker Desktop — it provides native `--network host` support. Enable OrbStack's built-in Kubernetes (no minikube needed). The container connects to it directly via `~/.kube/config`; no minikube shim is created.

For local Kubernetes development on **Linux/Windows**, run minikube on the **host** (not in the container):

```bash
# On the host — start minikube (one-time)
minikube start --driver=docker --memory=8192 --cpus=4

# Launch a container with host network access
claude-in-container --host-network --worktree myapp k8s-feature
```

Inside the container:
- `kubectl` and `tilt` are pre-installed
- `~/.kube/config` is mounted (read-write for context switching)
- `~/.minikube/` is mounted at its host path so cert references resolve
- A `minikube` shim is auto-created that returns the real Docker daemon address (discovered dynamically at launch)
- Tilt's port-forwards and web UI (localhost:10350) are accessible from your host browser

**Do not** install or start minikube inside the container — it runs on the host and the container connects to it via the shared config.

### Permission mode

On launch you'll be prompted:

```
Skip permissions? [Y/n]
```

Default is yes (`--dangerously-skip-permissions`) since the container provides isolation.

## What's mounted

### Per-project (read-write)

| Mount | Container path | Description |
|-------|---------------|-------------|
| Project directory | `/workspace` | Your repo or worktree |
| Config volume | `~/.claude` | Per-instance Claude state (sessions, history) |
| Base config volume | `~/.claude-base` (ro) | Base project config for auth seeding |

### Shared credentials (read-only)

| Mount | Container path | Description |
|-------|---------------|-------------|
| `.gitconfig` | `~/.gitconfig` | Git config (copied to writable location at startup) |
| SSH keys | `~/.ssh/` | Git over SSH |
| GitHub token | `GH_TOKEN` env var | From `~/.config/gh/token` |
| GitHub CLI config | `~/.config/gh/` | CLI config directory |
| AWS config | `~/.aws/config` | AWS profiles and settings |
| AWS credentials | `~/.aws/credentials` | AWS access keys |
| AWS SSO cache | `~/.aws/sso/cache/` | **Read-write** — shared across containers |
| AWS CLI cache | `~/.aws/cli/cache/` | **Read-write** — shared across containers |
| gcloud config | `~/.config/gcloud/` | Google Cloud SDK |
| Gemini CLI | `~/.gemini/` | OAuth credentials |
| Codex CLI | `~/.codex/` | Auth config |

### Conditional mounts

| Mount | Container path | When |
|-------|---------------|------|
| Docker socket | `/var/run/docker.sock` | `--docker` flag or `DOCKER_PROJECTS` config |
| Docker config | `~/.docker/` | `--docker` flag |
| Kube config | `~/.kube/config` | `--host-network` or `--docker` |
| Minikube certs | `~/.minikube/` (host path) | `--host-network` or `--docker` |
| Claude roles | `~/.claude/roles/` (ro) | If `ROLES_DIR` is configured |
| Forecast binary | `/usr/local/bin/forecast` (ro) | If `FORECAST_BIN` is configured |
| Forecast config | `/workspace/.forecast/` (ro) | If `.forecast/` exists in main repo |
| SSH agent | `/tmp/ssh-agent.sock` | If `SSH_AUTH_SOCK` is set |

### Shared cache volumes

These persist across all containers and survive restarts:

| Volume | Container path | Purpose |
|--------|---------------|---------|
| `claude-cache-npm` | `~/.npm` | npm package cache |
| `claude-cache-go` | `~/go/pkg/mod` | Go module cache |
| `claude-cache-pip` | `~/.cache/pip` | pip package cache |
| `claude-cache-playwright` | `~/.cache/ms-playwright` | Playwright browser binaries |

## Docker socket security

The Docker socket is **not mounted by default** because it grants host-level access (a container with the socket can escape isolation entirely).

Enable it when needed:

```bash
# Per-launch
claude-in-container --docker myapp

# Per-project (in config.sh)
DOCKER_PROJECTS=("myapp" "backend")

# Globally (in config.sh)
MOUNT_DOCKER_SOCKET="true"
```

## GitHub CLI in containers

The container can't access the host's keyring, so `gh` auth is passed via token file:

```bash
# On host (run once, or when token expires)
gh auth token > ~/.config/gh/token
```

The setup script does this automatically if `gh` is authenticated.

## Entrypoint behavior

On every container start, the entrypoint automatically:

1. Fixes `.claude` volume permissions if needed
2. Copies `.gitconfig` to a writable location and sets `safe.directory=*`
3. Seeds auth and settings from the base config volume (first run or refreshes credentials)
4. Symlinks `~/.claude.json` into the config volume for persistence
5. Installs npm/yarn/pnpm dependencies if `node_modules` is missing
6. Creates a minikube shim if `MINIKUBE_DOCKER_HOST` is set
7. Injects Figma MCP config into `settings.json` if `FIGMA_API_KEY` is set
8. Displays a project-colored banner with the project name

## Image contents

The Docker image includes:

| Category | Tools |
|----------|-------|
| Languages | Go 1.25, Node.js 20 (+ corepack for pnpm/yarn), Python 3 |
| Go tools | golangci-lint, buf CLI |
| Proto tools | protoc, protoc-gen-js, protoc-gen-grpc-web |
| Cloud CLIs | AWS CLI v2, GitHub CLI |
| Container tools | Docker CLI + Compose, kubectl, Tilt |
| AI CLIs | Claude Code, Gemini CLI, OpenAI Codex CLI |
| Testing | Playwright (Chromium + Firefox pre-installed) |
| Diagnostics | lsof, ss (iproute2), ps (procps), fuser/killall (psmisc) |

## Command reference

```
claude-in-container [flags] <command|project> [args...]

Modifier flags:
  --docker              Mount Docker socket
  --host-network        Use host network (implies --docker)
  --offline             Disable network

Commands:
  --build               Rebuild the Docker image
  --login <project>     Generate OAuth token for a project
  --shell <project>     Open a bash shell
  --worktree <p> <name> Create/resume a worktree instance
  --list                List running containers
  --stop <p> <name>     Stop worktree + clean up everything
  --prune <project>     Remove all stale worktrees
  -h, --help            Show usage

Direct launch:
  <project> [args...]   Start Claude in a project container
```
