# Windows Support Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make claude-containers work on Windows with Docker Desktop + Git Bash, with zero changes to container-side code (Dockerfile, entrypoint.sh).

**Architecture:** Add a Windows detection block near the top of each host-side script that sets `IS_WINDOWS=true` and defines a `winpath()` helper to convert MSYS paths (`/c/Users/...`) to Docker-compatible paths (`C:/Users/...`). Guard the 6 Linux-specific operations (getent, readlink -f, Docker socket test, SSH agent, id -u/id -g, symlink) behind `IS_WINDOWS` checks. Set `MSYS_NO_PATHCONV=1` before all `docker run` and `docker build` calls to prevent Git Bash from mangling colon-separated volume mount paths.

**Tech Stack:** Bash (Git Bash / MSYS2 on Windows), Docker Desktop for Windows

---

## Key Findings from Investigation

- `$HOME` in Git Bash = `/c/Users/devep` (MSYS path) — Docker mounts fail with this
- `MSYS_NO_PATHCONV=1` disables MSYS path mangling — Docker mounts work with `C:/Users/...` style paths
- `id -u` returns `197610` (MSYS synthetic UID) — Dockerfile default of `1000` is correct for Docker Desktop
- `getent` does not exist in Git Bash — needs fallback
- Docker Desktop exposes `/var/run/docker.sock` through its Linux VM — the `-S` socket test fails on Windows but the mount still works
- `readlink -f` works in Git Bash (MSYS2 coreutils)
- SSH agent on Windows uses named pipes, not Unix sockets — `$SSH_AUTH_SOCK` is unset

---

### Task 1: Add Windows detection and path helper to `claude-in-container`

**Files:**
- Modify: `claude-in-container:1-19`

**Step 1: Add Windows detection block after line 5 (SCRIPT_DIR)**

Insert after `SCRIPT_DIR="..."` and before config loading. This block:
1. Detects Windows via `uname -o` == `Msys`
2. Defines `winpath()` to convert `/c/Users/...` to `C:/Users/...`
3. Exports `MSYS_NO_PATHCONV=1` to stop Git Bash mangling Docker volume paths

```bash
# Windows (Git Bash / MSYS2) support
IS_WINDOWS=false
if [[ "$(uname -o 2>/dev/null)" == "Msys" ]]; then
    IS_WINDOWS=true
    export MSYS_NO_PATHCONV=1
fi

# Convert MSYS paths (/c/Users/...) to Windows paths (C:/Users/...) for Docker mounts.
# On Linux this is a no-op. Docker Desktop on Windows needs C:/ style paths.
winpath() {
    if [[ "$IS_WINDOWS" == "true" ]]; then
        echo "$1" | sed -E 's|^/([a-zA-Z])/|\U\1:/|'
    else
        echo "$1"
    fi
}
```

**Step 2: Verify the edit**

Run: `head -30 claude-in-container`
Expected: the detection block appears between SCRIPT_DIR and config loading.

**Step 3: Commit**

```bash
git add claude-in-container
git commit -m "feat: add Windows detection and winpath helper to launcher"
```

---

### Task 2: Fix `build_image()` for Windows in `claude-in-container`

**Files:**
- Modify: `claude-in-container:54-62` (the `build_image` function)

**Step 1: Replace build_image with Windows-aware version**

The three issues:
- `id -u` / `id -g` return MSYS synthetic UIDs (197610) — use defaults 1000:1000 on Windows
- `getent group docker` doesn't exist — use default GID 999 on Windows
- `$SCRIPT_DIR` path needs conversion for Docker build context

Replace the `build_image()` function body:

```bash
build_image() {
    echo "Building $IMAGE_NAME image..."
    local host_uid host_gid docker_gid build_context
    if [[ "$IS_WINDOWS" == "true" ]]; then
        host_uid=1000
        host_gid=1000
        docker_gid=999
        build_context="$(winpath "$SCRIPT_DIR")"
    else
        host_uid="$(id -u)"
        host_gid="$(id -g)"
        docker_gid="$(getent group docker | cut -d: -f3)"
        build_context="$SCRIPT_DIR"
    fi
    docker build \
        --build-arg HOST_UID="$host_uid" \
        --build-arg HOST_GID="$host_gid" \
        --build-arg DOCKER_GID="$docker_gid" \
        -t "$IMAGE_NAME" \
        "$build_context"
}
```

**Step 2: Test the build**

Run: `cd /c/Users/devep/Project/claude-containers && bash claude-in-container --build`
Expected: Docker image builds successfully with UID 1000, GID 1000, Docker GID 999.

**Step 3: Commit**

```bash
git add claude-in-container
git commit -m "feat: Windows-safe build_image with fallback UID/GID defaults"
```

---

### Task 3: Fix volume mounts in `run_container()` for Windows

**Files:**
- Modify: `claude-in-container:263-325` (host_mounts section of run_container)

**Step 1: Wrap all `$HOME`-based mount paths with `winpath()`**

Every `-v "$HOME/...":/container/path` mount needs the host side wrapped: `-v "$(winpath "$HOME/..."):/container/path"`.

Apply `winpath()` to every host-side volume path. The affected mounts:

```bash
    # Git config
    [[ -f "$HOME/.gitconfig" ]] && \
        host_mounts+=(-v "$(winpath "$HOME/.gitconfig")":/home/claude/.gitconfig:ro)

    # SSH keys (for git over SSH)
    [[ -d "$HOME/.ssh" ]] && \
        host_mounts+=(-v "$(winpath "$HOME/.ssh")":/home/claude/.ssh:ro)

    # GitHub CLI auth
    if [[ -f "$HOME/.config/gh/token" ]]; then
        host_mounts+=(-e "GH_TOKEN=$(cat "$HOME/.config/gh/token")")
    fi
    [[ -d "$HOME/.config/gh" ]] && \
        host_mounts+=(-v "$(winpath "$HOME/.config/gh")":/home/claude/.config/gh:ro)

    # Gemini CLI auth
    [[ -d "$HOME/.gemini" ]] && \
        host_mounts+=(-v "$(winpath "$HOME/.gemini")":/home/claude/.gemini:ro)

    # OpenAI Codex CLI auth
    [[ -d "$HOME/.codex" ]] && \
        host_mounts+=(-v "$(winpath "$HOME/.codex")":/home/claude/.codex:ro)
```

For Docker socket section — on Windows, skip the `-S` socket test (it's a named pipe, not a Unix socket) and use `/var/run/docker.sock` which Docker Desktop maps through its VM:

```bash
    if [[ "$needs_docker" == "true" ]]; then
        if [[ "$IS_WINDOWS" == "true" ]]; then
            # Docker Desktop maps the socket through its Linux VM
            host_mounts+=(-v //var/run/docker.sock:/var/run/docker.sock)
        else
            [[ -S /var/run/docker.sock ]] && \
                host_mounts+=(-v /var/run/docker.sock:/var/run/docker.sock)
        fi
        [[ -d "$HOME/.docker" ]] && \
            host_mounts+=(-v "$(winpath "$HOME/.docker")":/home/claude/.docker:ro)
    fi

    # GCloud
    [[ -d "$HOME/.config/gcloud" ]] && \
        host_mounts+=(-v "$(winpath "$HOME/.config/gcloud")":/home/claude/.config/gcloud:ro)
```

For AWS section:

```bash
    if [[ -d "$HOME/.aws" ]]; then
        [[ -f "$HOME/.aws/config" ]] && \
            host_mounts+=(-v "$(winpath "$HOME/.aws/config")":/home/claude/.aws/config:ro)
        [[ -f "$HOME/.aws/credentials" ]] && \
            host_mounts+=(-v "$(winpath "$HOME/.aws/credentials")":/home/claude/.aws/credentials:ro)
        mkdir -p "$HOME/.aws/cli/cache" "$HOME/.aws/sso/cache"
        host_mounts+=(-v "$(winpath "$HOME/.aws/cli/cache")":/home/claude/.aws/cli/cache)
        host_mounts+=(-v "$(winpath "$HOME/.aws/sso/cache")":/home/claude/.aws/sso/cache)
    fi
```

For SSH agent — skip on Windows (SSH keys are already mounted directly):

```bash
    # SSH agent forwarding (not supported on Windows — keys are mounted directly)
    if [[ "$IS_WINDOWS" != "true" ]] && [[ -n "${SSH_AUTH_SOCK:-}" ]]; then
        host_mounts+=(-v "$SSH_AUTH_SOCK":/tmp/ssh-agent.sock)
        host_mounts+=(-e SSH_AUTH_SOCK=/tmp/ssh-agent.sock)
    fi
```

**Step 2: Verify the edit**

Run: `grep -n 'winpath' claude-in-container | head -20`
Expected: ~15-20 lines with winpath calls in the mount section.

**Step 3: Commit**

```bash
git add claude-in-container
git commit -m "feat: winpath-wrap all volume mounts for Windows Docker Desktop"
```

---

### Task 4: Fix remaining path references in `run_container()`

**Files:**
- Modify: `claude-in-container:327-443` (roles, forecast, git worktree, kube mounts, and docker run)

**Step 1: Apply `winpath()` to roles, forecast, git worktree, and kube mounts**

Roles mounts:
```bash
    local roles_mounts=()
    if [[ -d "$ROLES_DIR" ]]; then
        roles_mounts+=(-v "$(winpath "$ROLES_DIR")":/workspace/.claude/roles:ro)
    fi
```

Forecast mounts:
```bash
    local forecast_mounts=()
    local forecast_bin="${FORECAST_BIN:-}"
    if [[ -n "$forecast_bin" && -f "$forecast_bin" ]]; then
        forecast_mounts+=(-v "$(winpath "$forecast_bin")":/usr/local/bin/forecast:ro)
        local forecast_cfg="$PROJECTS_DIR/$project_dir/.forecast"
        if [[ -d "$forecast_cfg" ]]; then
            forecast_mounts+=(-v "$(winpath "$forecast_cfg")":/workspace/.forecast:ro)
        fi
    fi
```

Git worktree mounts:
```bash
    local git_mounts=()
    if [[ -f "$full_path/.git" ]]; then
        local main_git_dir
        main_git_dir=$(cd "$full_path" && git rev-parse --git-common-dir 2>/dev/null)
        if [[ -n "$main_git_dir" && -d "$main_git_dir" ]]; then
            main_git_dir=$(cd "$full_path" && cd "$main_git_dir" && pwd)
            git_mounts+=(-v "$(winpath "$main_git_dir")":"$(winpath "$main_git_dir")")
        fi
    fi
```

Kubernetes mounts:
```bash
    if [[ "${HOST_NETWORK}" == "true" || "${DOCKER_SOCKET}" == "true" ]]; then
        [[ -f "$HOME/.kube/config" ]] && \
            host_mounts+=(-v "$(winpath "$HOME/.kube/config")":/home/claude/.kube/config)
        [[ -d "$HOME/.minikube" ]] && \
            host_mounts+=(-v "$(winpath "$HOME/.minikube")":"$(winpath "$HOME/.minikube")":ro)
    fi
```

Project directory mount in docker run:
```bash
        -v "$(winpath "$full_path")":/workspace \
```

Secrets env file:
```bash
    local secrets_env_flag=()
    if [[ -f "$SCRIPT_DIR/secrets.env" ]]; then
        secrets_env_flag+=(--env-file "$(winpath "$SCRIPT_DIR/secrets.env")")
    fi
```

**Step 2: Verify no unwrapped `$HOME` or `$PROJECTS_DIR` paths remain in volume mounts**

Run: `grep -n '\-v "$HOME\|  -v "$PROJECTS_DIR\| -v "$full_path\| -v "$SCRIPT_DIR\| -v "$ROLES_DIR\| -v "$forecast' claude-in-container`
Expected: zero matches — all should now use `winpath()`.

Run: `grep -n 'winpath' claude-in-container`
Expected: all volume mount host paths are wrapped.

**Step 3: Commit**

```bash
git add claude-in-container
git commit -m "feat: winpath-wrap roles, forecast, git, kube, and project mounts"
```

---

### Task 5: Fix `setup.sh` for Windows

**Files:**
- Modify: `setup.sh:1-115`

**Step 1: Add same Windows detection block after SCRIPT_DIR (line 4)**

Same `IS_WINDOWS`, `MSYS_NO_PATHCONV`, and `winpath()` block as Task 1.

**Step 2: Fix the docker build call (lines 59-64)**

Same pattern as Task 2 — use default UID/GID on Windows:

```bash
if [[ "$IS_WINDOWS" == "true" ]]; then
    docker build \
        --build-arg HOST_UID=1000 \
        --build-arg HOST_GID=1000 \
        --build-arg DOCKER_GID=999 \
        -t claude-dev \
        "$(winpath "$SCRIPT_DIR")"
else
    docker build \
        --build-arg HOST_UID="$(id -u)" \
        --build-arg HOST_GID="$(id -g)" \
        --build-arg DOCKER_GID="$(getent group docker | cut -d: -f3)" \
        -t claude-dev \
        "$SCRIPT_DIR"
fi
```

**Step 3: Fix the symlink section (lines 66-77)**

On Windows, skip the symlink and suggest adding the repo to PATH instead:

```bash
if [[ "$IS_WINDOWS" == "true" ]]; then
    echo "Add this directory to your Git Bash PATH in ~/.bashrc:"
    echo "  export PATH=\"$SCRIPT_DIR:\$PATH\""
    if ! echo "$PATH" | grep -q "$(basename "$SCRIPT_DIR")"; then
        echo ""
        echo "NOTE: $SCRIPT_DIR is not in your PATH yet."
    fi
else
    BIN_DIR="$HOME/.local/bin"
    mkdir -p "$BIN_DIR"
    ln -sf "$SCRIPT_DIR/claude-in-container" "$BIN_DIR/claude-in-container"
    echo "Symlinked claude-in-container to $BIN_DIR/"
    if ! echo "$PATH" | grep -q "$BIN_DIR"; then
        echo ""
        echo "NOTE: $BIN_DIR is not in your PATH. Add it:"
        echo "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc"
    fi
fi
```

**Step 4: Test setup.sh**

Run: `cd /c/Users/devep/Project/claude-containers && bash setup.sh`
Expected: prerequisites check passes, config validates, image builds, PATH instructions shown (no symlink error).

**Step 5: Commit**

```bash
git add setup.sh
git commit -m "feat: Windows support for setup.sh (UID/GID defaults, PATH instead of symlink)"
```

---

### Task 6: Fix `setup-project.sh` for Windows

**Files:**
- Modify: `setup-project.sh:1-368`

**Step 1: Add Windows detection block after SCRIPT_DIR (line 3)**

Same `IS_WINDOWS`, `MSYS_NO_PATHCONV`, and `winpath()` block.

**Step 2: Fix the docker build call (lines 330-336)**

Same pattern as Task 5 — guard with `IS_WINDOWS` for UID/GID defaults:

```bash
if [[ "$DO_BUILD" == "true" ]]; then
    echo "Building..."
    if [[ "$IS_WINDOWS" == "true" ]]; then
        docker build \
            --build-arg HOST_UID=1000 \
            --build-arg HOST_GID=1000 \
            --build-arg DOCKER_GID=999 \
            -t claude-dev \
            "$(winpath "$SCRIPT_DIR")"
    else
        docker build \
            --build-arg HOST_UID="$(id -u)" \
            --build-arg HOST_GID="$(id -g)" \
            --build-arg DOCKER_GID="$(getent group docker | cut -d: -f3)" \
            -t claude-dev \
            "$SCRIPT_DIR"
    fi
fi
```

**Step 3: Commit**

```bash
git add setup-project.sh
git commit -m "feat: Windows support for setup-project.sh docker build"
```

---

### Task 7: Smoke test — build image and launch a shell on Windows

**Files:**
- No file changes — this is a verification task

**Step 1: Build the image**

Run: `cd /c/Users/devep/Project/claude-containers && bash claude-in-container --build`
Expected: Image builds successfully.

**Step 2: Create a minimal config.sh for testing**

Create `config.sh` if not present:
```bash
PROJECTS_DIR="/c/Users/devep/Project"
declare -A PROJECTS=(
    [claude-containers]="claude-containers"
)
ROLES_DIR="$PROJECTS_DIR/claude-roles"
FORECAST_BIN=""
```

**Step 3: Launch a shell**

Run: `bash claude-in-container --shell claude-containers`
Expected: Container starts, colored banner shows, bash prompt appears. Inside container:
- `ls /workspace` shows the repo files
- `whoami` returns `claude`
- `claude --version` works
- `git status` works in /workspace

**Step 4: Verify credential mounts**

Inside container:
- `cat ~/.gitconfig` shows git config
- `ls ~/.ssh/` shows SSH keys
- `gh auth status` works (if token was set up)

**Step 5: Exit and verify cleanup**

Run: `exit`
Expected: container is removed (--rm flag).

**Step 6: Commit all remaining adjustments**

If any fixes were needed during smoke testing, commit them.

---

### Task 8: Update WINDOWS-ONBOARDING.md with final instructions

**Files:**
- Modify: `WINDOWS-ONBOARDING.md`

**Step 1: Replace the speculative content with tested, verified instructions**

Document:
1. Prerequisites (Docker Desktop, Git for Windows with Git Bash)
2. Clone and configure
3. Run `bash setup.sh`
4. Create `config.sh` and `secrets.env`
5. Build image: `bash claude-in-container --build`
6. First login: `bash claude-in-container --login <project>`
7. Daily use: `bash claude-in-container <project>`
8. Known limitations (no SSH agent forwarding, no minikube shim)

**Step 2: Commit**

```bash
git add WINDOWS-ONBOARDING.md
git commit -m "docs: finalize Windows onboarding instructions"
```
