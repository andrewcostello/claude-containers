# claude-containers

Run Claude Code in isolated Docker containers per project. Each project gets its own Claude account/login while sharing host credentials (git, gh, SSH, AWS) read-only.

## Features

- **Isolated Claude logins** — separate accounts per project (personal vs professional)
- **Filesystem isolation** — containers can only access their own project
- **Shared host credentials** — git, SSH, GitHub CLI, AWS, gcloud mounted read-only
- **Git worktree support** — spin up multiple Claude agents on the same project
- **Docker socket access** — manage devcontainers from inside Claude
- **Persistent sessions** — Claude state survives container restarts
- **Shared roles** — mount a common roles directory across all projects

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
- Claude Code subscription (for `claude setup-token`)

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
```

## Usage

```bash
# Log in to Claude for a project (first time only)
claude-in-container --login myapp

# Start Claude in a project
claude-in-container myapp

# Start with a prompt
claude-in-container myapp "fix the login bug"

# Spawn a worktree instance (branches from origin/main)
claude-in-container --worktree myapp feature-name

# Open a shell in the container
claude-in-container --shell myapp

# List running containers
claude-in-container --list

# Rebuild the Docker image
claude-in-container --build
```

### Permission mode

On launch you'll be prompted:

```
Skip permissions? [Y/n]
```

Default is yes (`--dangerously-skip-permissions`) since the container provides isolation.

### Multiple agents on one project

Use `--worktree` to create isolated git worktrees, each with its own container:

```bash
claude-in-container --worktree myapp auth-refactor
claude-in-container --worktree myapp fix-payments
```

Worktrees branch from `origin/main` by default. Clean up with:

```bash
git -C ~/Project/myapp-repo worktree remove ~/Project/myapp-repo-wt-auth-refactor
```

## What's mounted

| Mount | Source | Mode | Scope |
|-------|--------|------|-------|
| Project directory | `~/Project/<repo>` | read-write | per-project |
| Claude config | Docker volume | read-write | per-project |
| `.gitconfig` | `~/.gitconfig` | read-only | shared |
| SSH keys | `~/.ssh/` | read-only | shared |
| GitHub token | `~/.config/gh/token` | env var | shared |
| AWS credentials | `~/.aws/` | read-only | shared |
| gcloud config | `~/.config/gcloud/` | read-only | shared |
| Docker socket | `/var/run/docker.sock` | read-write | shared |
| Claude roles | configured dir | read-only | shared |
| Forecast binary | configured path | read-only | shared |

## GitHub CLI in containers

The container can't access the host's keyring, so `gh` auth is passed via token file:

```bash
# On host (run once, or when token expires)
gh auth token > ~/.config/gh/token
```

The setup script does this automatically if `gh` is authenticated.

## Image contents

The Docker image includes: Go 1.25, Node.js 20, Python 3, golangci-lint, buf, gh CLI, Docker CLI + Compose, and Claude Code (native installer).
