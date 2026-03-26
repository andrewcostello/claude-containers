#!/bin/bash
set -e

# Fix ownership of .claude dir if mounted as a fresh volume (created by root)
if [ -d "$HOME/.claude" ] && [ ! -w "$HOME/.claude" ]; then
    echo "Fixing .claude directory permissions..."
    sudo chown -R "$(id -u):$(id -g)" "$HOME/.claude"
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

exec claude "$@"
