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
    eval "$var=\"${value:-$default}\""
}

prompt_secret() {
    local var="$1" prompt_text="$2"
    printf "${CYAN}%s${NC}: " "$prompt_text"
    read -rs value </dev/tty
    echo ""
    eval "$var=\"$value\""
}

prompt_yn() {
    local var="$1" prompt_text="$2" default="${3:-y}"
    local hint="[Y/n]"
    [[ "$default" == "n" ]] && hint="[y/N]"
    printf "${CYAN}%s${NC} %s: " "$prompt_text" "$hint"
    read -r value </dev/tty
    value="${value:-$default}"
    [[ "${value,,}" == "y" ]] && eval "$var=true" || eval "$var=false"
}

section() {
    echo ""
    echo -e "${BOLD}═══ $1 ═══${NC}"
    echo ""
}

# --- Header ---
echo ""
echo -e "${BOLD}claude-containers project setup${NC}"
echo "This wizard configures a new project for use with claude-in-container."
echo ""

# --- Load existing config if present ---
SECRETS_FILE="$SCRIPT_DIR/secrets.env"
CONFIG_FILE="$SCRIPT_DIR/config.sh"

if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# ========================================
# 1. Project basics
# ========================================
section "Project"

prompt PROJECTS_DIR "Where do your project repos live?" "${PROJECTS_DIR:-$HOME/Project}"

prompt PROJECT_KEY "Short name for this project (e.g., evenplay, rr)"
prompt PROJECT_DIR "Repo directory name under $PROJECTS_DIR" "$PROJECT_KEY"

FULL_PATH="$PROJECTS_DIR/$PROJECT_DIR"
if [[ ! -d "$FULL_PATH" ]]; then
    echo -e "${YELLOW}Directory $FULL_PATH does not exist.${NC}"
    prompt_yn DO_CLONE "Clone it now?" "y"
    if [[ "$DO_CLONE" == "true" ]]; then
        prompt CLONE_URL "Git clone URL"
        echo "Cloning..."
        git clone "$CLONE_URL" "$FULL_PATH"
    else
        echo "You'll need to clone it before using claude-in-container."
    fi
fi

# ========================================
# 2. GitHub CLI
# ========================================
section "GitHub"

GH_OK=false
if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
    echo -e "${GREEN}gh CLI is authenticated.${NC}"
    mkdir -p "$HOME/.config/gh"
    gh auth token > "$HOME/.config/gh/token" 2>/dev/null
    chmod 600 "$HOME/.config/gh/token"
    echo "Token saved to ~/.config/gh/token"
    GH_OK=true
else
    echo "gh CLI is not authenticated."
    prompt_yn DO_GH "Set up GitHub CLI now?" "y"
    if [[ "$DO_GH" == "true" ]]; then
        if ! command -v gh &>/dev/null; then
            echo "Install gh first: https://cli.github.com/"
        else
            echo "Running gh auth login..."
            gh auth login </dev/tty
            if gh auth status &>/dev/null 2>&1; then
                mkdir -p "$HOME/.config/gh"
                gh auth token > "$HOME/.config/gh/token" 2>/dev/null
                chmod 600 "$HOME/.config/gh/token"
                echo -e "${GREEN}GitHub authenticated and token saved.${NC}"
                GH_OK=true
            fi
        fi
    fi
fi

# ========================================
# 3. AWS
# ========================================
section "AWS"

if [[ -f "$HOME/.aws/config" ]]; then
    echo "Existing AWS config found. Profiles:"
    grep '^\[profile' "$HOME/.aws/config" 2>/dev/null | sed 's/\[profile /  /;s/\]//' || echo "  (none)"
    echo ""
fi

prompt_yn SETUP_AWS "Configure AWS SSO for this project?" "n"
if [[ "$SETUP_AWS" == "true" ]]; then
    prompt AWS_PROFILE "AWS SSO profile name (e.g., evenplay-admin)"
    prompt AWS_SSO_URL "AWS SSO start URL"
    prompt AWS_SSO_REGION "AWS SSO region" "us-east-1"
    prompt AWS_ACCOUNT_ID "AWS account ID"
    prompt AWS_ROLE "AWS SSO role name" "AdministratorAccess"
    prompt AWS_DEFAULT_REGION "Default region for this profile" "us-east-1"

    mkdir -p "$HOME/.aws"
    # Append profile if it doesn't exist
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
        echo "Profile $AWS_PROFILE already exists in ~/.aws/config"
    fi

    echo ""
    echo "Login now with: aws sso login --profile $AWS_PROFILE"
    prompt_yn DO_SSO_LOGIN "Login now?" "y"
    if [[ "$DO_SSO_LOGIN" == "true" ]]; then
        aws sso login --profile "$AWS_PROFILE" </dev/tty || echo -e "${YELLOW}SSO login failed — you can retry later.${NC}"
    fi
fi

# ========================================
# 4. Jira / Forecast
# ========================================
section "Jira / Forecast"

prompt_yn SETUP_JIRA "Configure Jira integration for this project?" "n"
JIRA_TOKEN=""
if [[ "$SETUP_JIRA" == "true" ]]; then
    prompt JIRA_URL "Jira instance URL (e.g., https://myorg.atlassian.net)"
    prompt JIRA_EMAIL "Jira email"
    prompt JIRA_PROJECT_KEY "Jira project key (e.g., SMG)"
    prompt_secret JIRA_TOKEN "Jira API token (from https://id.atlassian.com/manage-profile/security/api-tokens)"

    # Create .forecast config in the project
    if [[ -d "$FULL_PATH" ]]; then
        FORECAST_DIR="$FULL_PATH/.forecast"
        if [[ ! -d "$FORECAST_DIR" ]]; then
            mkdir -p "$FORECAST_DIR"
            cat > "$FORECAST_DIR/config.yaml" << EOF
# Forecast Configuration - $PROJECT_KEY
project_name: "$PROJECT_KEY"
project_type: "Backend Service + Frontend"
team_size: 3
team_capacity: 8

jira:
  url: $JIRA_URL
  email: $JIRA_EMAIL
  api_token: \${JIRA_API_TOKEN}
  project_key: $JIRA_PROJECT_KEY
EOF
            echo -e "${GREEN}Created $FORECAST_DIR/config.yaml${NC}"
        else
            echo "Forecast config already exists at $FORECAST_DIR"
        fi
    fi
fi

# ========================================
# 5. Claude auth
# ========================================
section "Claude Code Auth"

CLAUDE_TOKEN=""
if [[ -f "$SECRETS_FILE" ]] && grep -q 'CLAUDE_CODE_OAUTH_TOKEN=.' "$SECRETS_FILE" 2>/dev/null; then
    echo "Existing Claude OAuth token found in secrets.env"
    prompt_yn REGEN_TOKEN "Generate a new one?" "n"
    if [[ "$REGEN_TOKEN" == "true" ]]; then
        prompt_secret CLAUDE_TOKEN "Paste your Claude OAuth token (from --login setup-token)"
    fi
else
    echo "No Claude OAuth token configured."
    echo "You can generate one with: claude-in-container --login $PROJECT_KEY"
    echo "Then paste the token here, or skip and add it later to secrets.env."
    prompt_secret CLAUDE_TOKEN "Claude OAuth token (or press Enter to skip)"
fi

# ========================================
# 6. Figma (optional)
# ========================================
section "Figma (optional)"

FIGMA_KEY=""
if [[ -f "$SECRETS_FILE" ]] && grep -q 'FIGMA_API_KEY=.' "$SECRETS_FILE" 2>/dev/null; then
    echo "Existing Figma API key found in secrets.env"
else
    prompt_yn SETUP_FIGMA "Configure Figma integration?" "n"
    if [[ "$SETUP_FIGMA" == "true" ]]; then
        prompt_secret FIGMA_KEY "Figma Personal Access Token (from Figma → Account Settings → Personal Access Tokens)"
    fi
fi

# ========================================
# 7. Docker socket
# ========================================
section "Docker Socket"

echo "The Docker socket is not mounted by default (security)."
echo "Projects using devcontainers, compose, or Tilt need it."
prompt_yn NEEDS_DOCKER "Does $PROJECT_KEY need Docker socket access?" "n"

# ========================================
# 8. Write config files
# ========================================
section "Writing configuration"

# --- config.sh ---
if [[ -f "$CONFIG_FILE" ]]; then
    # Add project to existing config if not already present
    if grep -q "\[$PROJECT_KEY\]" "$CONFIG_FILE" 2>/dev/null; then
        echo "Project $PROJECT_KEY already in config.sh"
    else
        # Insert into PROJECTS array
        sed -i "/^declare -A PROJECTS=(/a\\    [$PROJECT_KEY]=\"$PROJECT_DIR\"" "$CONFIG_FILE"
        echo -e "${GREEN}Added $PROJECT_KEY to config.sh${NC}"
    fi

    # Add to DOCKER_PROJECTS if needed
    if [[ "$NEEDS_DOCKER" == "true" ]]; then
        if grep -q 'DOCKER_PROJECTS=' "$CONFIG_FILE" 2>/dev/null; then
            # Append to existing array if not already present
            if ! grep -q "\"$PROJECT_KEY\"" "$CONFIG_FILE" 2>/dev/null; then
                sed -i "s/DOCKER_PROJECTS=(\(.*\))/DOCKER_PROJECTS=(\1 \"$PROJECT_KEY\")/" "$CONFIG_FILE"
                echo "Added $PROJECT_KEY to DOCKER_PROJECTS"
            fi
        else
            echo "DOCKER_PROJECTS=(\"$PROJECT_KEY\")" >> "$CONFIG_FILE"
            echo "Created DOCKER_PROJECTS with $PROJECT_KEY"
        fi
    fi
else
    cat > "$CONFIG_FILE" << EOF
# claude-containers configuration (generated by setup-project.sh)

PROJECTS_DIR="$PROJECTS_DIR"

declare -A PROJECTS=(
    [$PROJECT_KEY]="$PROJECT_DIR"
)

ROLES_DIR="\$PROJECTS_DIR/claude-roles"
FORECAST_BIN=""
EOF
    if [[ "$NEEDS_DOCKER" == "true" ]]; then
        echo "DOCKER_PROJECTS=(\"$PROJECT_KEY\")" >> "$CONFIG_FILE"
    fi
    echo -e "${GREEN}Created config.sh${NC}"
fi

# --- secrets.env ---
if [[ ! -f "$SECRETS_FILE" ]]; then
    touch "$SECRETS_FILE"
    chmod 600 "$SECRETS_FILE"
fi

# Helper: set or update a key in secrets.env
set_secret() {
    local key="$1" value="$2"
    [[ -z "$value" ]] && return
    if grep -q "^${key}=" "$SECRETS_FILE" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$SECRETS_FILE"
    else
        echo "${key}=${value}" >> "$SECRETS_FILE"
    fi
}

set_secret "JIRA_API_TOKEN" "$JIRA_TOKEN"
set_secret "CLAUDE_CODE_OAUTH_TOKEN" "$CLAUDE_TOKEN"
set_secret "FIGMA_API_KEY" "$FIGMA_KEY"

echo -e "${GREEN}Updated secrets.env${NC}"

# ========================================
# 9. Build image if needed
# ========================================
section "Docker Image"

if docker image inspect claude-dev &>/dev/null; then
    echo "Docker image claude-dev already exists."
    prompt_yn DO_BUILD "Rebuild it?" "n"
else
    prompt_yn DO_BUILD "Build the Docker image now?" "y"
fi

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
            --build-arg DOCKER_GID="$(gid="$(getent group docker 2>/dev/null | cut -d: -f3)"; echo "${gid:-999}")" \
            -t claude-dev \
            "$SCRIPT_DIR"
    fi
fi

# ========================================
# 10. Summary
# ========================================
section "Setup Complete"

echo -e "${GREEN}Project $PROJECT_KEY is ready.${NC}"
echo ""
echo "Quick start:"
echo "  claude-in-container --login $PROJECT_KEY    # First-time Claude auth"
echo "  claude-in-container $PROJECT_KEY             # Start Claude"
echo "  claude-in-container --worktree $PROJECT_KEY my-feature"
echo ""

if [[ "$NEEDS_DOCKER" == "true" ]]; then
    echo "Docker socket: enabled for $PROJECT_KEY"
fi

if [[ -n "$JIRA_TOKEN" ]]; then
    echo "Jira: configured ($JIRA_PROJECT_KEY at $JIRA_URL)"
fi

if [[ "$GH_OK" == "true" ]]; then
    echo "GitHub: authenticated"
fi

if [[ "$SETUP_AWS" == "true" ]]; then
    echo "AWS: profile $AWS_PROFILE configured"
fi

echo ""
