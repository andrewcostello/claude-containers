# Windows Onboarding for claude-containers

Run Claude Code in isolated Docker containers on Windows, using Git Bash and Docker Desktop.

## Prerequisites

1. **Docker Desktop** — installed and running with Linux containers (default mode)
2. **Git for Windows** — includes Git Bash (MSYS2), which runs all the scripts
3. **GitHub CLI** (optional) — `gh` for GitHub integration inside containers

## Setup

Open **Git Bash** and run:

```bash
git clone https://github.com/andrewcostello/claude-containers.git ~/Project/claude-containers
cd ~/Project/claude-containers
```

### Configure your projects

```bash
cp config.example.sh config.sh
```

Edit `config.sh` with your projects:

```bash
PROJECTS_DIR="$HOME/Project"

declare -A PROJECTS=(
    [myapp]="myapp-repo"
    [backend]="backend-mono"
)

ROLES_DIR="$PROJECTS_DIR/claude-roles"  # or "" to disable
FORECAST_BIN=""                          # or path to forecast binary
```

### Configure secrets (optional)

```bash
cp secrets.example.env secrets.env
```

Edit `secrets.env` with your API tokens:

```bash
CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-...   # from --login setup-token
JIRA_API_TOKEN=your_token
FIGMA_API_KEY=figd_...                      # enables Figma MCP automatically
```

### Build the Docker image

```bash
bash setup.sh
```

This validates prerequisites, builds the `claude-dev` image, and sets up GitHub CLI tokens if available.

**Note:** On Windows, `setup.sh` prints PATH instructions instead of creating a symlink. Add the repo directory to your `~/.bashrc`:

```bash
export PATH="$HOME/Project/claude-containers:$PATH"
```

Or run commands with `bash claude-in-container ...` directly.

### GitHub CLI token (for container access)

```bash
gh auth login                              # if not already authenticated
gh auth token > ~/.config/gh/token
```

## Usage

All commands run in Git Bash:

```bash
# First-time auth — generates an OAuth token, add it to secrets.env
claude-in-container --login myapp

# Start Claude in a project
claude-in-container myapp

# Start with a prompt
claude-in-container myapp "fix the login bug"

# Open a bash shell in the container
claude-in-container --shell myapp

# Rebuild the Docker image
claude-in-container --build

# Git worktrees for concurrent agents
claude-in-container --worktree myapp auth-refactor
claude-in-container --worktree myapp fix-payments
```

## How Windows Support Works

The scripts detect Windows (Git Bash / MSYS2) and apply three adaptations:

1. **Path translation** — A `winpath()` helper converts MSYS paths (`/c/Users/...`) to Docker-compatible paths (`C:/Users/...`). On Linux it's a no-op.

2. **MSYS_NO_PATHCONV=1** — Exported to prevent Git Bash from mangling the colon-separated `-v host:container` volume mount syntax.

3. **UID/GID defaults** — On Windows, `id -u` returns synthetic MSYS values and `getent` doesn't exist. The scripts use defaults (1000:1000, Docker GID 999) which match Docker Desktop's Linux VM.

No changes were needed to the Dockerfile or entrypoint.sh — they run inside a Linux container regardless of host OS.

## What's Mounted (same as Linux)

- Project directory at `/workspace`
- Git config, SSH keys (read-only)
- GitHub CLI token (via `GH_TOKEN` env var)
- AWS config/credentials (config read-only, SSO cache read-write)
- Gemini CLI, Codex CLI auth (read-only)
- Claude roles (read-only, if configured)
- Shared cache volumes (npm, Go, pip, Playwright)

## Known Limitations on Windows

| Feature | Status | Notes |
|---------|--------|-------|
| SSH agent forwarding | Not supported | SSH keys are mounted directly instead — works for most use cases |
| Minikube / Tilt | Untested | `--host-network` flag works but minikube shim may need adjustment for Windows Docker Desktop |
| Docker socket | Works | Docker Desktop maps `/var/run/docker.sock` through its Linux VM |
| File watchers | May hit limits | Docker Desktop file watching on Windows bind mounts can be slow for large repos |
| Interactive TTY | Requires Git Bash | Run from Git Bash terminal, not CMD or PowerShell (the scripts use bash) |

## Verified Test Results

Tested on Windows 11 Home with Docker Desktop 28.5.2, Git 2.52.0, Git Bash 5.2.37:

- [x] Docker image builds successfully with default UID/GID
- [x] Container starts with colored project banner
- [x] `/workspace` correctly mounts the project directory
- [x] `claude --version` works inside container (2.1.90)
- [x] Git config mounted and readable
- [x] SSH keys mounted and readable
- [x] AWS config mounted and readable
- [x] Entrypoint handles `safe.directory` for git
- [x] Container auto-removes on exit (`--rm`)
