# claude-containers configuration
# Copy this to config.sh and customize for your machine:
#   cp config.example.sh config.sh

# Where your projects live
PROJECTS_DIR="$HOME/Project"

# Map of short names to directory names under PROJECTS_DIR
# Format: [shortname]="dirname"
declare -A PROJECTS=(
    [awevoke]="awevoke"
    [evenplay]="evenplay-mono"
    [rr]="rr-mono"
)

# Shared Claude roles repo (cloned separately)
# Set to "" to disable
ROLES_DIR="$PROJECTS_DIR/claude-roles"

# Forecast CLI binary path (set to "" to disable)
FORECAST_BIN="$PROJECTS_DIR/forecast/forecast"

# Resource limits (optional — these are the defaults)
# CONTAINER_MEMORY="8g"
# CONTAINER_CPUS="4"

# Mount Docker socket by default (set to "true" if most projects need it)
# Can always override per-launch with --docker flag
# MOUNT_DOCKER_SOCKET="false"

# Projects that always need the Docker socket (e.g., for devcontainers / compose)
# DOCKER_PROJECTS=("evenplay" "rr")
