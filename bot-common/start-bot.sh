#!/bin/bash
# Shared bot start script — called by each bot's systemd service
# Usage: start-bot.sh /path/to/bot/dir
BOT_DIR="${1:?Usage: start-bot.sh /path/to/bot/dir}"
source "$BOT_DIR/bot.conf"

export PATH=/usr/local/bin:/usr/bin:/bin:$HOME/.bun/bin:$HOME/.npm-global/bin
export HOME="$HOME"

# Source bot-specific env vars
[ -f "$BOT_DIR/.env" ] && . "$BOT_DIR/.env"

cd "$BOT_DIR"

tmux kill-session -t "$BOT_NAME" 2>/dev/null

SESSION_NAME="$BOT_LABEL-$(date '+%Y%m%d-%H%M')"

# Build claude command with optional env overrides and extra flags
CLAUDE_ENV=""
[ -n "$CLAUDE_CONFIG_DIR" ] && CLAUDE_ENV="CLAUDE_CONFIG_DIR=$CLAUDE_CONFIG_DIR "
[ -n "$TELEGRAM_STATE_DIR" ] && CLAUDE_ENV="${CLAUDE_ENV}TELEGRAM_STATE_DIR=$TELEGRAM_STATE_DIR "

CLAUDE_CMD="${CLAUDE_ENV}claude --channels plugin:telegram@claude-plugins-official --remote-control --dangerously-skip-permissions --name \"$SESSION_NAME\""
[ -n "$CLAUDE_EXTRA_FLAGS" ] && CLAUDE_CMD="$CLAUDE_CMD $CLAUDE_EXTRA_FLAGS"

tmux new-session -d -s "$BOT_NAME" "$CLAUDE_CMD"

# Wait for initialization (up to 90s)
for i in $(seq 1 90); do
    if tmux capture-pane -t "$BOT_NAME" -p 2>/dev/null | grep -q "remote-control is active"; then
        break
    fi
    sleep 1
done

sleep 5  # buffer for MCP servers and channels

tmux send-keys -t "$BOT_NAME" "$STARTUP_PROMPT" Enter

# Mark bot as idle in fleet-state (if helper is present)
[ -x "$(dirname "$0")/fleet-state-update.sh" ] && "$(dirname "$0")/fleet-state-update.sh" "$BOT_NAME" "idle" || true

echo "$BOT_LABEL started"
