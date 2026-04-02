#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Windows (Git Bash / MSYS2) support
IS_WINDOWS=false
if [[ "$(uname -o 2>/dev/null)" == "Msys" ]]; then
    IS_WINDOWS=true
    export MSYS_NO_PATHCONV=1
fi

winpath() {
    if [[ "$IS_WINDOWS" == "true" ]]; then
        echo "$1" | sed -E 's|^/([a-zA-Z])/|\U\1:/|'
    else
        echo "$1"
    fi
}

# Colors
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

prompt() {
    local var="$1" prompt_text="$2" default="${3:-}"
    if [[ -n "$default" ]]; then
        printf "${CYAN}%s${NC} [%s]: " "$prompt_text" "$default"
    else
        printf "${CYAN}%s${NC}: " "$prompt_text"
    fi
    read -r value </dev/tty
    printf -v "$var" '%s' "${value:-$default}"
}

prompt_secret() {
    local var="$1" prompt_text="$2"
    printf "${CYAN}%s${NC}: " "$prompt_text"
    read -rs value </dev/tty
    echo ""
    printf -v "$var" '%s' "$value"
}

prompt_yn() {
    local var="$1" prompt_text="$2" default="${3:-y}"
    local hint="[Y/n]"
    [[ "$default" == "n" ]] && hint="[y/N]"
    printf "${CYAN}%s${NC} %s: " "$prompt_text" "$hint"
    read -r value </dev/tty
    value="${value:-$default}"
    [[ "${value,,}" == "y" ]] && printf -v "$var" '%s' "true" || printf -v "$var" '%s' "false"
}

section() {
    echo ""
    echo -e "${BOLD}═══ $1 ═══${NC}"
    echo ""
}

check_cmd() {
    local cmd="$1" name="${2:-$1}"
    if command -v "$cmd" &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $name: $(command -v "$cmd")"
        return 0
    else
        echo -e "  ${RED}✗${NC} $name: not found"
        return 1
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}claude-containers: Windows Setup${NC}"
echo "Complete setup for running Claude Code in Docker containers on Windows."
echo ""

SECRETS_FILE="$SCRIPT_DIR/secrets.env"
CONFIG_FILE="$SCRIPT_DIR/config.sh"
GITHUB_USER=""

# ══════════════════════════════════════════════════════════════════════════════
section "1. Checking Prerequisites"
# ══════════════════════════════════════════════════════════════════════════════

prereqs_ok=true

check_cmd git "Git" || prereqs_ok=false
check_cmd docker "Docker" || prereqs_ok=false

if [[ "$prereqs_ok" != "true" ]]; then
    echo ""
    echo -e "${RED}Missing prerequisites. Run bootstrap-windows.ps1 first:${NC}"
    echo "  powershell -ExecutionPolicy Bypass -File bootstrap-windows.ps1"
    exit 1
fi

# Check Docker daemon is running
echo ""
echo "Checking Docker daemon..."
if docker info &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} Docker daemon is running"
else
    echo -e "  ${RED}✗${NC} Docker daemon is not running"
    echo ""
    echo "Start Docker Desktop and wait for it to finish loading, then re-run this script."
    exit 1
fi

# Check optional tools
echo ""
echo "Optional tools (already installed):"
check_cmd gh "GitHub CLI" || true
check_cmd claude "Claude Code" || true
check_cmd aws "AWS CLI" || true
check_cmd minikube "minikube" || true

# ══════════════════════════════════════════════════════════════════════════════
section "2. Optional Tool Installation"
# ══════════════════════════════════════════════════════════════════════════════

echo "These tools are installed on the Windows host for credential sharing."
echo "The Docker image already has its own copies for use inside containers."
echo ""
echo -e "${YELLOW}NOTE: If you install anything here, restart Git Bash afterwards to pick it up.${NC}"
echo ""

if ! command -v gh &>/dev/null; then
    prompt_yn INSTALL_GH "Install GitHub CLI? (for PR/issue workflows)" "y"
    if [[ "$INSTALL_GH" == "true" ]]; then
        echo "Installing GitHub CLI..."
        cmd.exe //c "winget install --id GitHub.cli --accept-source-agreements --accept-package-agreements"
        echo -e "${GREEN}GitHub CLI installed. Restart Git Bash to pick it up.${NC}"
    fi
else
    echo -e "GitHub CLI: ${GREEN}already installed${NC}"
fi

echo ""
if ! command -v aws &>/dev/null; then
    prompt_yn INSTALL_AWS "Install AWS CLI? (for AWS credential sharing)" "n"
    if [[ "$INSTALL_AWS" == "true" ]]; then
        echo "Installing AWS CLI..."
        cmd.exe //c "winget install --id Amazon.AWSCLI --accept-source-agreements --accept-package-agreements"
        echo -e "${GREEN}AWS CLI installed. Restart Git Bash to pick it up.${NC}"
    fi
else
    echo -e "AWS CLI: ${GREEN}already installed${NC}"
fi

echo ""
if ! command -v minikube &>/dev/null; then
    prompt_yn INSTALL_MK "Install minikube? (only if you do local Kubernetes dev)" "n"
    if [[ "$INSTALL_MK" == "true" ]]; then
        echo "Installing minikube..."
        cmd.exe //c "winget install --id Kubernetes.minikube --accept-source-agreements --accept-package-agreements"
        echo -e "${GREEN}minikube installed.${NC}"
    fi
else
    echo -e "minikube: ${GREEN}already installed${NC}"
fi

# ══════════════════════════════════════════════════════════════════════════════
section "3. Companion Repos"
# ══════════════════════════════════════════════════════════════════════════════

prompt PROJECTS_DIR "Where do your project repos live?" "${PROJECTS_DIR:-$HOME/Project}"
mkdir -p "$PROJECTS_DIR"

# Claude roles
ROLES_DIR="$PROJECTS_DIR/claude-roles"
echo ""
if [[ -d "$ROLES_DIR" ]]; then
    echo -e "claude-roles: ${GREEN}already cloned${NC} at $ROLES_DIR"
else
    prompt_yn CLONE_ROLES "Clone claude-roles? (shared Claude role definitions)" "y"
    if [[ "$CLONE_ROLES" == "true" ]]; then
        echo "Cloning claude-roles..."
        git clone https://github.com/andrewcostello/claude-roles.git "$ROLES_DIR"
        echo -e "${GREEN}Cloned to $ROLES_DIR${NC}"
    else
        ROLES_DIR=""
    fi
fi

# Forecast tool
FORECAST_BIN=""
FORECAST_DIR="$PROJECTS_DIR/forecast"
echo ""
if [[ -d "$FORECAST_DIR" ]]; then
    echo -e "forecast: ${GREEN}already present${NC} at $FORECAST_DIR"
    if [[ -f "$FORECAST_DIR/forecast" ]]; then
        FORECAST_BIN="$FORECAST_DIR/forecast"
    fi
else
    prompt_yn CLONE_FORECAST "Clone forecast tool? (Jira integration for sprint planning)" "n"
    if [[ "$CLONE_FORECAST" == "true" ]]; then
        prompt FORECAST_REPO "Forecast repo URL" "https://github.com/andrewcostello/forecast.git"
        echo "Cloning forecast..."
        git clone "$FORECAST_REPO" "$FORECAST_DIR"
        if [[ -f "$FORECAST_DIR/forecast" ]]; then
            FORECAST_BIN="$FORECAST_DIR/forecast"
        fi
        echo -e "${GREEN}Cloned to $FORECAST_DIR${NC}"
    fi
fi

# ══════════════════════════════════════════════════════════════════════════════
section "4. Credentials"
# ══════════════════════════════════════════════════════════════════════════════

# --- GitHub CLI ---
echo -e "${BOLD}GitHub CLI${NC}"
GH_OK=false
if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
    echo -e "${GREEN}gh CLI is authenticated.${NC}"
    GITHUB_USER=$(gh api user --jq '.login' 2>/dev/null || echo "")
    if [[ -n "$GITHUB_USER" ]]; then
        echo "  Logged in as: $GITHUB_USER"
    fi
    mkdir -p "$HOME/.config/gh"
    gh auth token > "$HOME/.config/gh/token" 2>/dev/null
    chmod 600 "$HOME/.config/gh/token" 2>/dev/null || true
    echo "  Token saved to ~/.config/gh/token"
    GH_OK=true
elif command -v gh &>/dev/null; then
    echo "gh CLI is installed but not authenticated."
    prompt_yn DO_GH "Authenticate GitHub CLI now?" "y"
    if [[ "$DO_GH" == "true" ]]; then
        echo "Running gh auth login..."
        gh auth login --web </dev/tty
        if gh auth status &>/dev/null 2>&1; then
            GITHUB_USER=$(gh api user --jq '.login' 2>/dev/null || echo "")
            mkdir -p "$HOME/.config/gh"
            gh auth token > "$HOME/.config/gh/token" 2>/dev/null
            chmod 600 "$HOME/.config/gh/token" 2>/dev/null || true
            echo -e "${GREEN}GitHub authenticated and token saved.${NC}"
            GH_OK=true
        fi
    fi
else
    echo -e "${YELLOW}GitHub CLI not installed. Skipping.${NC}"
fi

# --- AWS ---
echo ""
echo -e "${BOLD}AWS${NC}"
if [[ -f "$HOME/.aws/config" ]]; then
    echo "Existing AWS config found. Profiles:"
    grep '^\[profile' "$HOME/.aws/config" 2>/dev/null | sed 's/\[profile /  /;s/\]//' || echo "  (none)"
    echo ""
fi

SETUP_AWS=false
if command -v aws &>/dev/null; then
    prompt_yn SETUP_AWS "Configure AWS SSO?" "n"
else
    echo -e "${YELLOW}AWS CLI not installed. Skipping.${NC}"
fi

if [[ "$SETUP_AWS" == "true" ]]; then
    prompt AWS_PROFILE "AWS SSO profile name (e.g., myapp-admin)"
    prompt AWS_SSO_URL "AWS SSO start URL"
    prompt AWS_SSO_REGION "AWS SSO region" "us-east-1"
    prompt AWS_ACCOUNT_ID "AWS account ID"
    prompt AWS_ROLE "AWS SSO role name" "AdministratorAccess"
    prompt AWS_DEFAULT_REGION "Default region" "us-east-1"

    mkdir -p "$HOME/.aws"
    if ! grep -q "\[profile $AWS_PROFILE\]" "$HOME/.aws/config" 2>/dev/null; then
        cat >> "$HOME/.aws/config" << EOF

[profile $AWS_PROFILE]
sso_start_url = $AWS_SSO_URL
sso_region = $AWS_SSO_REGION
sso_account_id = $AWS_ACCOUNT_ID
sso_role_name = $AWS_ROLE
region = $AWS_DEFAULT_REGION
output = json
EOF
        echo -e "${GREEN}Added profile $AWS_PROFILE to ~/.aws/config${NC}"
    else
        echo "Profile $AWS_PROFILE already exists."
    fi

    prompt_yn DO_SSO_LOGIN "Login to AWS SSO now?" "y"
    if [[ "$DO_SSO_LOGIN" == "true" ]]; then
        aws sso login --profile "$AWS_PROFILE" </dev/tty || echo -e "${YELLOW}SSO login failed — retry later.${NC}"
    fi
fi

# --- Claude OAuth ---
echo ""
echo -e "${BOLD}Claude Code Auth${NC}"
CLAUDE_TOKEN=""
if [[ -f "$SECRETS_FILE" ]] && grep -q 'CLAUDE_CODE_OAUTH_TOKEN=.' "$SECRETS_FILE" 2>/dev/null; then
    echo "Existing Claude OAuth token found in secrets.env"
else
    echo "Claude containers need an OAuth token for authentication."
    echo "You have two options:"
    echo "  1. Skip now, run 'claude-in-container --login <project>' later"
    echo "  2. Paste a token if you already have one"
    echo ""
    prompt_secret CLAUDE_TOKEN "Claude OAuth token (or press Enter to skip)"
fi

# --- Jira ---
echo ""
echo -e "${BOLD}Jira${NC}"
JIRA_TOKEN=""
prompt_yn SETUP_JIRA "Configure Jira integration?" "n"
if [[ "$SETUP_JIRA" == "true" ]]; then
    prompt_secret JIRA_TOKEN "Jira API token (from https://id.atlassian.com/manage-profile/security/api-tokens)"
fi

# --- Figma ---
echo ""
echo -e "${BOLD}Figma${NC}"
FIGMA_KEY=""
prompt_yn SETUP_FIGMA "Configure Figma integration?" "n"
if [[ "$SETUP_FIGMA" == "true" ]]; then
    prompt_secret FIGMA_KEY "Figma Personal Access Token (Figma → Account Settings → Personal Access Tokens)"
fi

# ══════════════════════════════════════════════════════════════════════════════
section "5. Project Configuration"
# ══════════════════════════════════════════════════════════════════════════════

echo "Configure which projects to use with claude-in-container."
echo "Each project maps a short name to a repo directory under $PROJECTS_DIR."
echo ""

# Collect projects
declare -A NEW_PROJECTS=()
DOCKER_PROJECT_LIST=()

add_another=true
while [[ "$add_another" == "true" ]]; do
    prompt PROJECT_KEY "Project short name (e.g., myapp, backend)"
    prompt PROJECT_DIR "Repo directory name under $PROJECTS_DIR" "$PROJECT_KEY"

    FULL_PATH="$PROJECTS_DIR/$PROJECT_DIR"
    if [[ ! -d "$FULL_PATH" ]]; then
        echo -e "${YELLOW}Directory $FULL_PATH does not exist.${NC}"
        prompt_yn DO_CLONE "Clone it now?" "y"
        if [[ "$DO_CLONE" == "true" ]]; then
            prompt CLONE_URL "Git clone URL"
            echo "Cloning..."
            git clone "$CLONE_URL" "$FULL_PATH"
        fi
    else
        echo -e "  ${GREEN}Found:${NC} $FULL_PATH"
    fi

    NEW_PROJECTS[$PROJECT_KEY]="$PROJECT_DIR"

    prompt_yn NEEDS_DOCKER "Does $PROJECT_KEY need Docker socket access?" "n"
    if [[ "$NEEDS_DOCKER" == "true" ]]; then
        DOCKER_PROJECT_LIST+=("$PROJECT_KEY")
    fi

    echo ""
    prompt_yn add_another "Add another project?" "n"
done

# Write config.sh
echo ""

SKIP_CONFIG=false
if [[ -f "$CONFIG_FILE" ]]; then
    echo -e "${YELLOW}config.sh already exists.${NC}"
    prompt_yn OVERWRITE_CONFIG "Overwrite it?" "n"
    if [[ "$OVERWRITE_CONFIG" != "true" ]]; then
        echo "Keeping existing config.sh"
        SKIP_CONFIG=true
    fi
fi

if [[ "$SKIP_CONFIG" != "true" ]]; then
    echo "Writing config.sh..."

    PROJECTS_ENTRIES=""
    for key in "${!NEW_PROJECTS[@]}"; do
        PROJECTS_ENTRIES+="    [$key]=\"${NEW_PROJECTS[$key]}\"\n"
    done

    DOCKER_PROJECTS_LINE=""
    if [[ ${#DOCKER_PROJECT_LIST[@]} -gt 0 ]]; then
        DOCKER_PROJECTS_LINE="DOCKER_PROJECTS=("
        for dp in "${DOCKER_PROJECT_LIST[@]}"; do
            DOCKER_PROJECTS_LINE+="\"$dp\" "
        done
        DOCKER_PROJECTS_LINE="${DOCKER_PROJECTS_LINE% })"
    fi

    cat > "$CONFIG_FILE" << EOF
# claude-containers configuration (generated by windows-setup.sh)

PROJECTS_DIR="$PROJECTS_DIR"

declare -A PROJECTS=(
$(echo -en "$PROJECTS_ENTRIES"))

ROLES_DIR="${ROLES_DIR:-}"
FORECAST_BIN="${FORECAST_BIN:-}"
EOF

    if [[ -n "$DOCKER_PROJECTS_LINE" ]]; then
        echo "$DOCKER_PROJECTS_LINE" >> "$CONFIG_FILE"
    fi

    echo -e "${GREEN}Created config.sh${NC}"
fi

# Write secrets.env
echo "Writing secrets.env..."
if [[ ! -f "$SECRETS_FILE" ]]; then
    touch "$SECRETS_FILE"
    chmod 600 "$SECRETS_FILE" 2>/dev/null || true
fi

set_secret() {
    local key="$1" value="$2"
    [[ -z "$value" ]] && return
    # Remove existing line then append (avoids sed injection with special chars in tokens)
    grep -v "^${key}=" "$SECRETS_FILE" > "${SECRETS_FILE}.tmp" 2>/dev/null || true
    mv "${SECRETS_FILE}.tmp" "$SECRETS_FILE"
    printf '%s=%s\n' "$key" "$value" >> "$SECRETS_FILE"
    chmod 600 "$SECRETS_FILE" 2>/dev/null || true  # Best-effort; NTFS ignores Unix perms
}

set_secret "CLAUDE_CODE_OAUTH_TOKEN" "$CLAUDE_TOKEN"
set_secret "JIRA_API_TOKEN" "$JIRA_TOKEN"
set_secret "FIGMA_API_KEY" "$FIGMA_KEY"

echo -e "${GREEN}Updated secrets.env${NC}"

# ══════════════════════════════════════════════════════════════════════════════
section "6. Build & Test"
# ══════════════════════════════════════════════════════════════════════════════

# Build Docker image
echo "Building the claude-dev Docker image..."
echo "This installs Go, Node, Python, cloud CLIs, AI CLIs, and Playwright."
echo "First build takes 5-10 minutes. Subsequent builds use cache."
echo ""

docker build \
    --build-arg HOST_UID=1000 \
    --build-arg HOST_GID=1000 \
    --build-arg DOCKER_GID=999 \
    -t claude-dev \
    "$(winpath "$SCRIPT_DIR")"

echo ""
echo -e "${GREEN}Docker image built successfully.${NC}"

# Smoke test
echo ""
echo "Running smoke test..."

# Pick the first project for testing
FIRST_PROJECT=""
for key in "${!NEW_PROJECTS[@]}"; do
    FIRST_PROJECT="$key"
    break
done

FIRST_DIR="${NEW_PROJECTS[$FIRST_PROJECT]}"
TEST_PATH="$PROJECTS_DIR/$FIRST_DIR"

if [[ -d "$TEST_PATH" ]]; then
    SMOKE_OUTPUT=$(MSYS_NO_PATHCONV=1 docker run --rm \
        --name claude-smoketest \
        -v "$(winpath "$TEST_PATH")":/workspace \
        -v "$(winpath "$HOME/.gitconfig")":/home/claude/.gitconfig:ro \
        -v claude-config-smoketest:/home/claude/.claude \
        -v claude-config-smoketest:/home/claude/.claude-base:ro \
        -e CLAUDE_PROJECT=smoketest \
        claude-dev --version 2>&1) || true

    docker volume rm claude-config-smoketest &>/dev/null || true

    if echo "$SMOKE_OUTPUT" | grep -q "Claude Code"; then
        echo -e "  ${GREEN}✓${NC} Container starts successfully"
        echo -e "  ${GREEN}✓${NC} Claude Code works inside container"
        CLAUDE_VER=$(echo "$SMOKE_OUTPUT" | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)
        echo "  Claude Code version: $CLAUDE_VER"
    else
        echo -e "  ${YELLOW}⚠${NC} Smoke test returned unexpected output:"
        echo "  $SMOKE_OUTPUT"
    fi
else
    echo -e "  ${YELLOW}Skipping smoke test — project directory $TEST_PATH not found.${NC}"
fi

# Add to PATH
echo ""
BASHRC="$HOME/.bashrc"
if ! grep -q "claude-containers" "$BASHRC" 2>/dev/null; then
    prompt_yn ADD_PATH "Add claude-in-container to your PATH in ~/.bashrc?" "y"
    if [[ "$ADD_PATH" == "true" ]]; then
        echo "" >> "$BASHRC"
        echo "# claude-containers" >> "$BASHRC"
        echo "export PATH=\"$SCRIPT_DIR:\$PATH\"" >> "$BASHRC"
        echo -e "${GREEN}Added to ~/.bashrc. Run 'source ~/.bashrc' or restart Git Bash.${NC}"
    fi
else
    echo -e "PATH: ${GREEN}already configured in ~/.bashrc${NC}"
fi

# ══════════════════════════════════════════════════════════════════════════════
section "Setup Complete"
# ══════════════════════════════════════════════════════════════════════════════

echo -e "${GREEN}claude-containers is ready to use!${NC}"
echo ""
echo "Quick start:"
for key in "${!NEW_PROJECTS[@]}"; do
    echo "  claude-in-container --login $key    # First-time Claude auth"
    echo "  claude-in-container $key             # Start Claude"
    break
done
echo ""
echo "Worktrees (multiple agents on one project):"
for key in "${!NEW_PROJECTS[@]}"; do
    echo "  claude-in-container --worktree $key my-feature"
    break
done
echo ""

if [[ "$GH_OK" == "true" ]]; then
    echo -e "GitHub: ${GREEN}authenticated${NC}${GITHUB_USER:+ as $GITHUB_USER}"
fi
if [[ "$SETUP_AWS" == "true" ]]; then
    echo -e "AWS: ${GREEN}profile $AWS_PROFILE configured${NC}"
fi
if [[ -n "$CLAUDE_TOKEN" ]]; then
    echo -e "Claude OAuth: ${GREEN}configured${NC}"
else
    echo -e "Claude OAuth: ${YELLOW}not set — run 'claude-in-container --login <project>' next${NC}"
fi
if [[ -n "$JIRA_TOKEN" ]]; then
    echo -e "Jira: ${GREEN}configured${NC}"
fi
if [[ -n "$FIGMA_KEY" ]]; then
    echo -e "Figma: ${GREEN}configured${NC}"
fi
echo ""
echo "For more details, see WINDOWS-ONBOARDING.md"
echo ""
