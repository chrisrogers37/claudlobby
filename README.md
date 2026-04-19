# claudlobby

A multi-bot Claude Code fleet running on a single always-on Linux or macOS host (originally designed on a Raspberry Pi 5 — see [`docs/pi-setup-guide.md`](docs/pi-setup-guide.md) — and portable to Mac mini and other hosts). Always-on AI assistants connected via Telegram, each with specialized roles, isolated contexts, and shared infrastructure.

## What This Is

A system for running multiple Claude Code instances as persistent bots on a single always-on host, each with:
- Its own **Telegram bot** for communication
- Its own **MCP servers** (GitHub, Notion, Gmail, Shopify, etc.)
- Its own **persona and skills** defined in CLAUDE.md
- **Shared infrastructure** for starting, monitoring, and restarting bots

The bots operate in Telegram group chats where some listen to everything (`requireMention: false`) and others only respond when @mentioned (`requireMention: true`). This creates a natural hierarchy — a manager bot that converses freely and worker bots that activate on demand.

## What This Repo Includes — And Doesn't

**Included:**
- `bot-common/` — OS-agnostic lifecycle scripts, fleet-state tracking, Telegram helpers, bootstrap tooling
- `manager/` — canonical manager scaffold with 11 orchestration skills pre-installed
- `examples/worker/` — worker template with full Lifecycle / Context / Comms patterns
- `examples/global-skills/` — skills that need to land in `~/.claude/skills/` globally (`mission`, `autonomous-sprint`)
- `docs/first-run-bootstrap.md` — the zero-to-ripping walkthrough

**You install separately** (these are the big gaps people hit on a fresh clone):
- **Claudefather or equivalent** (`<your-claudefather-repo>`) — the global library of ~50 skills (`/simplify`, `/review-pr`, `/review-changes`, `/tech-debt`, `/session-handoff`, `/worktree`, `/development-retro`, etc.), 8 agents, and 4 hooks. **This is the single biggest reason a fleet "rips"** — without it, your bots are missing most of their muscle. Install via `./install.sh` inside the cloned repo.
- **[Claude Code](https://docs.anthropic.com/en/docs/claude-code)** — the CLI itself + OAuth login (or `ANTHROPIC_API_KEY`).
- **[Telegram channel plugin](https://github.com/anthropics/claude-plugins-official)** — `claude plugin install telegram@claude-plugins-official`.
- **Your secrets** — GitHub PAT, Notion token, Slack token, BotFather tokens (one per bot).

👉 **See [docs/first-run-bootstrap.md](docs/first-run-bootstrap.md) for the full sequence.**

## Architecture

```
┌─────────────────────────────────────────────────────┐
│            Always-on host (Pi 5 / Mac mini / …)      │
│                                                     │
│  ~/claudlobby/                                        │
│  ├── bot-common/          Shared start/keepalive    │
│  ├── bot-a/               Manager bot (Opus)         │
│  ├── bot-b/               Specialist bot (Opus)      │
│  ├── bot-c/               Engineer bot (Opus)        │
│  ├── bot-d/               Another engineer (Opus)    │
│  └── bot-e/               Code reviewer (Sonnet)     │
│                                                     │
│  Each bot = systemd service + tmux session           │
│           + Telegram channel + MCP servers            │
└──────────────────────┬──────────────────────────────┘
                       │
          ┌────────────┼────────────┐
          ▼            ▼            ▼
    ┌──────────┐ ┌──────────┐ ┌──────────┐
    │ Telegram │ │ Telegram │ │ Telegram │
    │ Group 1  │ │ Group 2  │ │ Group 3  │
    │ Domain A │ │ Domain B │ │ Eng Team │
    └──────────┘ └──────────┘ └──────────┘
```

## How It Works

### Bot Lifecycle

Each bot is a systemd service that launches a tmux session running Claude Code with the Telegram channel plugin:

1. **systemd** starts the bot on boot (or manual `systemctl start`)
2. **bot-common/start-bot.sh** reads `bot.conf`, sets up env vars, launches Claude in tmux
3. **Claude Code** connects to Telegram and MCP servers, reads CLAUDE.md for persona/instructions
4. **Keepalive cron** checks every 30 min: restarts dead sessions, nudges idle ones

### Multi-Bot Telegram

Multiple bots coexist in group chats using the Telegram channel plugin's access controls:

- **Manager bots** (`requireMention: false`): hear all messages, conversational
- **Worker bots** (`requireMention: true`): silent until @mentioned
- Each bot uses `TELEGRAM_STATE_DIR` to isolate its Telegram state (tokens, access lists, inbox)

### Task Dispatch

The manager bot orchestrates workers via **tmux send-keys** (reliable, instant) rather than Telegram (which can drop messages):

```bash
# Manager dispatches to worker
tmux send-keys -t work-eng-bot 'Fix the failing test in src/api/auth.ts and create a PR' Enter

# Worker reports back via report-back.sh
~/claudlobby/bot-common/report-back.sh "work-eng" "DONE" "Fixed auth test, PR #42" "pr:https://github.com/org/repo/pull/42"
```

## Quick Start

The full walkthrough lives at **[docs/first-run-bootstrap.md](docs/first-run-bootstrap.md)**.

Condensed flow:

```bash
# 1. Prereqs
brew install bun uv tmux jq gh            # macOS; see bootstrap doc for Linux
npm install -g @anthropic-ai/claude-code
claude /login

# 2. Clone + claudefather + plugin
git clone https://github.com/chrisrogers37/claudlobby.git ~/claudlobby
git clone <your-claudefather-repo> /tmp/claudefather && (cd /tmp/claudefather && ./install.sh)
claude plugin marketplace add anthropics/claude-plugins-official
claude plugin install telegram@claude-plugins-official

# 3. Optional global skills (needed for /autonomous-sprint)
cp -r ~/claudlobby/examples/global-skills/mission ~/.claude/skills/
cp -r ~/claudlobby/examples/global-skills/autonomous-sprint ~/.claude/skills/

# 4. Bootstrap your manager + workers
~/claudlobby/bot-common/bootstrap-bot.sh mgr manager   --telegram-token <...> --group-chat-id <...>
~/claudlobby/bot-common/bootstrap-bot.sh eng-a worker  --telegram-token <...> --group-chat-id <...>
~/claudlobby/bot-common/bootstrap-bot.sh rev-a worker  --telegram-token <...> --group-chat-id <...>

# 5. Fill in CLAUDE.md + .mcp.json + service unit + pair each bot → you're live.
```


## Directory Structure

```
claudlobby/
├── bot-common/                   # Shared lifecycle + helpers (OS-agnostic)
│   ├── start-bot.sh              # tmux + claude launcher (called by service unit)
│   ├── keepalive.sh              # Dead-session restart + idle nudge
│   ├── report-back.sh            # Worker → manager tmux reports (+ fleet-state update)
│   ├── tg-post.sh                # Bash → Telegram API w/ parse_mode=Markdown
│   ├── fleet-state.json          # Central "who's doing what" ledger
│   ├── fleet-state-update.sh     # Updater (called by start-bot + report-back)
│   ├── sprint-trigger.sh         # Schedule-driven /autonomous-sprint nudger
│   └── bootstrap-bot.sh          # One-shot per-bot scaffolder
│
├── manager/                      # Canonical manager scaffold
│   ├── bot.conf                  # Template w/ <PLACEHOLDERS>
│   ├── CLAUDE.md                 # Generic manager persona + orchestration rules
│   ├── .mcp.json.template        # GitHub + Notion + Slack stubs
│   └── .claude/
│       ├── settings.local.json
│       └── skills/               # 11 orchestration skills
│           ├── dispatch/ fleet-status/ lifecycle/
│           ├── autonomous-sprint/ data-alert-sweep/ deploy-status/ prs/
│           ├── restart/ sweep/ status/
│           └── _telegram-formatting.md
│
├── examples/
│   ├── worker/                   # Worker template (role-agnostic)
│   ├── global-skills/            # Install to ~/.claude/skills/ — mission, autonomous-sprint
│   ├── optional-personal-skills/ # Personal-assistant examples: briefing, triage
│   ├── optional-personal-scripts/  # evening-audit, finance-presync
│   ├── scripts/                  # Generic ops scripts
│   ├── access.json               # Telegram access template
│   └── bot.service               # Systemd unit template
│
└── docs/
    ├── first-run-bootstrap.md    # The zero-to-ripping walkthrough
    ├── pi-setup-guide.md
    ├── integrations.md
    ├── notion-integration.md
    ├── advanced-patterns.md
    └── bot-archetypes.md
```

## Key Concepts

### Naming and Personality

Each bot can have a unique name and personality. The directory name is the technical identifier — the persona lives in CLAUDE.md and the Telegram display name:

- **Directory:** `~/claudlobby/my-bot/` (technical, used by systemd/tmux/crons)
- **CLAUDE.md:** "You are Sage, a meticulous code reviewer who..." (how the bot sees itself — pick any persona)
- **Telegram @BotFather:** Set the display name and username (how everyone else sees it)

Give bots distinct personalities — a sarcastic engineer, a methodical reviewer, a high-energy business rep. The persona in CLAUDE.md shapes every interaction. Bots with strong personalities are more memorable and easier to work with in group chats.

### bot.conf

Each bot has a `bot.conf` that the shared scripts read:

```bash
BOT_NAME="my-bot"                    # tmux session name
BOT_SERVICE="my-bot"                 # systemd service name
BOT_LABEL="MY-BOT"                   # display label in logs
BOT_DIR="/home/user/claudlobby/my-bot" # absolute path to bot dir
TELEGRAM_STATE_DIR="/home/user/.claude/channels/telegram-my-bot"
CLAUDE_CONFIG_DIR=""                 # set for separate Claude auth
CLAUDE_EXTRA_FLAGS=""                # e.g., "--model sonnet" for cheaper bots
STARTUP_PROMPT="You just started. Read your CLAUDE.md and greet the team."
```

### CLAUDE_CONFIG_DIR (Multi-Account)

Run bots under different Claude accounts by pointing to a separate config directory:

```bash
# In bot.conf for a work bot:
CLAUDE_CONFIG_DIR="/home/user/.claude-work"
```

This gives the bot its own auth, plugins, and channel state. Requires a one-time `claude auth login` in the new config dir. Symlink shared skills: `ln -s ~/.claude/skills ~/.claude-work/skills`

### TELEGRAM_STATE_DIR (Multi-Bot Telegram)

Each bot needs its own Telegram state to avoid conflicts:

```
~/.claude/channels/telegram-assistant/   # Bot 1
~/.claude/channels/telegram-company/     # Bot 2
~/.claude/channels/telegram-engineer/    # Bot 3
```

The `TELEGRAM_STATE_DIR` env var tells the Telegram plugin where to find its token and access config. Set it in `bot.conf` and the shared `start-bot.sh` passes it to Claude.

Reference: [anthropics/claude-code#37173](https://github.com/anthropics/claude-code/issues/37173)

### requireMention (Group Chat Routing)

Control which bots respond to which messages in a shared group:

```json
{
  "groups": {
    "-100XXXXXXXXXX": {
      "requireMention": true,
      "allowFrom": []
    }
  }
}
```

- `requireMention: false` — bot processes ALL messages (manager/conversational bots)
- `requireMention: true` — bot only responds to @mentions and replies (worker bots)

**Important:** You must also disable Group Privacy on @BotFather (`/setprivacy` → Disable) for the bot to receive group messages at all.

### Skill Scoping

Skills can be global (shared by all bots) or project-scoped (only visible to one bot):

```
~/.claude/skills/              # Global — all bots see these
~/claudlobby/my-bot/.claude/skills/  # Project-scoped — only this bot
```

Use this to give each bot only the skills it needs. Personal assistant skills (briefing, finance, calendar) shouldn't be visible to engineer bots.

## Multi-Bot Patterns

### Manager + Workers

One bot orchestrates, others execute:

```
Manager (requireMention: false)
  ├── Worker A (requireMention: true) — engineering tasks
  ├── Worker B (requireMention: true) — code reviews
  └── Worker C (requireMention: true) — specialized work
```

The manager dispatches via tmux (reliable), workers report results to Telegram (visible).

### Independent Specialists

Bots in separate groups for different domains:

```
Domain A group:  Bot A (e.g., personal assistant, life management)
Domain B group:  Bot B (e.g., business ops, customer service, e-commerce)
Engineering group: Manager + engineers + code reviewer
```

### Code Review Pipeline

Engineer creates PR → Manager dispatches reviewer → Reviewer posts findings → Manager routes feedback:

```bash
# Manager dispatches review
tmux send-keys -t code-reviewer-bot 'Review PR #42 at https://github.com/org/repo/pull/42. Use /review-pr.' Enter
```

## Resource Planning

Per-bot resource cost (Pi 5 reference — similar on Mac mini / small Linux hosts):

| Component | RAM |
|-----------|-----|
| Claude Code process | ~580 MB |
| MCP servers (varies) | ~200-500 MB |
| **Total per bot** | **~800 MB - 1.1 GB** |

| Fleet Size | Estimated RAM | 16 GB host |
|-----------|---------------|-------------|
| 2 bots | ~2-3 GB | Comfortable |
| 3-4 bots | ~4-5 GB | Good |
| 5-6 bots | ~6-8 GB | Monitor closely |
| 7+ bots | ~8+ GB | Consider swap or second Pi |

Tips:
- Give worker bots fewer MCP servers (just GitHub) to reduce memory
- Use `--model sonnet` for bots that don't need Opus (code reviewer, simple tasks)
- Add swap space as safety net: `sudo dphys-swapfile` (2-4 GB recommended)

## Security Hardening

Recommended for any Pi running always-on bots:

```bash
# Lock down secret files
chmod 600 ~/.env ~/claudlobby/*/.env ~/claudlobby/*/.mcp.json

# Disable SSH password auth (key-only)
sudo sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart ssh

# Install firewall
sudo apt install ufw
sudo ufw default deny incoming
sudo ufw allow from 192.168.x.0/24 to any port 22  # SSH from LAN
sudo ufw enable

# Install brute-force protection
sudo apt install fail2ban
sudo systemctl enable --now fail2ban

# Disable unnecessary services
sudo systemctl disable --now cups cups-browsed ModemManager
```

## Telegram Reliability

The Claude Code Telegram plugin has known message-dropping issues ([#36477](https://github.com/anthropics/claude-code/issues/36477), [#37933](https://github.com/anthropics/claude-code/issues/37933)). Mitigations that help:

1. **Keepalive cron** — nudges idle sessions every 30 min (included in bot-common)
2. **Group chats with `requireMention: false`** — significantly more reliable than DMs
3. **Supergroup format** — make bots admin to auto-upgrade to supergroup
4. **Staggered keepalives** — don't run all bots' keepalives at the same minute
5. **Auto-restart** — keepalive detects dead sessions and runs `systemctl restart`

For critical interactions, use **Remote Control** (`--remote-control` flag, included by default) as a reliable fallback.

## Documentation

- **[Pi Setup Guide](docs/pi-setup-guide.md)** — Complete setup: OS, Node.js, Bun, Claude Code, CLIs (Vercel, Railway, Neon, DigitalOcean, dbt), security hardening, swap, cron templates
- **[Bot Archetypes](docs/bot-archetypes.md)** — Proven configurations for manager, engineer, code reviewer, designer, and business bots. MCP servers, skills, and Telegram settings for each.
- **[Integrations Guide](docs/integrations.md)** — Setup for every MCP server: GitHub, Notion, Gmail, Calendar, Slack, Shopify, Printify, Home Assistant, Docker, Spotify, Granola, and DevOps CLIs
- **[Notion Integration](docs/notion-integration.md)** — Deep dive: connecting to Notion, programmatic database creation, multi-workspace isolation, recommended database structures
- **[Advanced Patterns](docs/advanced-patterns.md)** — Lifecycle orchestration, alert sweep, triage, inter-bot communication, automated audits, pre-stop handoff, visual crawl, multi-account, data pre-sync, Telegram formatting

### Global Skills Layer

Bot-specific skills live in each bot's directory. General-purpose development skills (code review, worktrees, security audits, deployment tools) are shared globally via your claudefather-equivalent repo — a global Claude Code configuration repo that manages skills, hooks, and agents installed to `~/.claude/`. See the [bot archetypes doc](docs/bot-archetypes.md) for which skills each bot type needs.

## Example Configurations

The `examples/` directory contains templates for every file a bot needs:

| File | Purpose |
|------|---------|
| `bot.conf` | Bot identity and paths |
| `CLAUDE.md` | Persona, skills, behavior rules |
| `.mcp.json` | MCP server connections (GitHub, Notion, Gmail, Shopify, Slack, Home Assistant) |
| `bot.service` | Systemd service unit |
| `access.json` | Telegram group/DM access control |
| `settings.local.json` | Claude tool permissions |
| `skills/` | Orchestration skills: dispatch, fleet-status, briefing, lifecycle, triage, data-alert-sweep, visual-crawl |
| `scripts/` | Automation scripts: pre-stop-handoff, git-pull-all, evening-audit, finance-presync |
| `_telegram-formatting.md` | Telegram markdown reference |

## Use Cases

This system is flexible enough for many configurations:

- **Personal assistant** — Calendar, email, tasks, smart home, finance tracking
- **Business operations** — Customer service, order management, e-commerce (Shopify/Printify)
- **Engineering team** — Code reviews, PR management, data pipeline monitoring, automated fixes
- **Content management** — Social media scheduling, content calendar, analytics
- **DevOps/SRE** — Deployment monitoring (Vercel, Railway, DO), database management (Neon, Snowflake)
- **Multi-tenant** — Separate bots for separate businesses/clients, fully isolated

## License

MIT
