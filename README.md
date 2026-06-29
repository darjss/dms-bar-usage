# DMS AI Usage

A [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) bar widget that shows **Codex** and **Claude Code** usage limits in the DankBar. Click the robot icon for a compact popout with per-window usage bars, reset countdowns, and credit balances.

## What it does

Codex and Claude Code both enforce rolling rate-limit windows that are easy to blow past without noticing. This widget surfaces those limits where you already look — the DankBar — so you can see at a glance how much of each window you've burned and when it resets.

A small Go binary (`dms-ai-usage`) fetches live usage from each provider's OAuth API and prints one JSON blob to stdout. The QML widget shells out to that binary on a timer and renders the result. No API keys to configure — it reads the OAuth tokens that the Codex and Claude CLIs already store on disk.

## Features

- **Codex** — 5-hour window, weekly window, and credit balance
- **Claude Code** — 5-hour session, weekly window, model-specific weekly (Sonnet / Opus / OAuth Apps, whichever is active), and extra-usage / spend credits
- Color-coded status bars: green (< 70 %), amber (70–90 %), red (≥ 90 %)
- Auto-refresh on a configurable interval (2–60 s, default 5 s)
- Toggle individual providers or the credits card from settings
- Two-column compact popout (520 × 400)
- Graceful fallback: if a live fetch fails, the widget shows the last cached result and marks it stale

## Requirements

| Dependency | Why |
|---|---|
| [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) | Plugin host (Quickshell-based) |
| `go` >= 1.23 | Build the `dms-ai-usage` data binary |
| `sqlite3` | Codex fallback (reads `~/.codex/logs_2.sqlite`) |
| Codex CLI logged in (`~/.codex/auth.json`) | Codex usage via OAuth API |
| Claude Code logged in (`~/.claude/.credentials.json`) | Claude usage via OAuth API |

## How it works

```
DankBar widget (QML)
        │  shells out on a timer
        ▼
dms-ai-usage (Go binary)
        │
        ├── Codex:  OAuth API (wham/usage)  →  logs_2.sqlite  →  cache
        └── Claude: OAuth API (api.anthropic.com/api/oauth/usage)  →  cache
        │
        ▼
   one JSON blob to stdout
```

**Codex** (`codex.go`) reads `~/.codex/auth.json`, refreshes the OAuth token if it's older than 8 days, and calls the `wham/usage` endpoint. If that fails it falls back to parsing the latest `codex.rate_limits` websocket event out of `~/.codex/logs_2.sqlite` via the `sqlite3` CLI. If that also fails it serves the last cached result from `~/.cache/dms-ai-usage/codex.json` and flags it stale.

**Claude Code** (`claude.go`) reads `~/.claude/.credentials.json` and calls Anthropic's (undocumented) OAuth usage endpoint. If that fails it serves the cached result from `~/.cache/dms-ai-usage/claude.json` and flags it stale.

The widget parses the JSON and renders one `UsageCard` per window. Each card composes a `UsageBar` (the colored progress bar) plus an icon, percentage, and reset-countdown footer.

## Install

### Manual (this repo)

```bash
git clone git@github.com:darjss/dms-bar-usage.git
cd dms-bar-usage
make install-all   # builds binary + symlinks plugin into DMS plugin dir
dms restart
```

`make install-all` does two things:

1. `make install` — builds `dms-ai-usage` and installs it to `~/.local/bin/`
2. `make install-plugin` — symlinks `plugin/` into `~/.config/DankMaterialShell/plugins/AiUsage`

| Make target | What it does |
|---|---|
| `make build` | Compile the Go binary |
| `make install` | Build + install binary to `~/.local/bin/dms-ai-usage` |
| `make install-plugin` | Symlink `plugin/` into the DMS plugins directory |
| `make install-all` | Both of the above |
| `make uninstall` | Remove binary and plugin symlink |
| `make clean` | Remove build artifact |

After install, toggle the widget in DMS Settings → **Plugins** → **AI Usage**.

### From the DMS plugin registry (once published)

```bash
dms plugins install aiUsage
dms restart
```

Or via DMS Settings → **Plugins** → **Browse** → search "AI Usage".

## Settings

| Setting | Default | Description |
|---|---|---|
| Refresh interval | 5 s | How often to poll for usage data (2–60 s) |
| Show Codex | on | Display Codex usage cards in the popout |
| Show Claude Code | on | Display Claude Code usage cards in the popout |
| Show credits | on | Display credit balance in the popout |

## Project layout

```
.
├── main.go              # CLI entry — calls codex + claude fetchers, prints JSON
├── codex.go             # Codex usage: OAuth API → logs_2.sqlite → cache fallback
├── claude.go            # Claude usage: OAuth API → cache fallback
├── go.mod               # module dms-ai-usage, go 1.23
├── Makefile             # build / install / install-plugin targets
├── screenshot.png       # used by the plugin registry listing
└── plugin/
    ├── plugin.json          # DMS plugin manifest (id, name, component, settings)
    ├── AiUsageWidget.qml    # Bar widget + popout (composes UsageCard)
    ├── AiUsageSettings.qml  # Settings panel (refresh interval, toggles)
    ├── UsageBar.qml         # Reusable progress bar component
    └── UsageCard.qml        # Reusable usage card component (icon, value, bar, footer)
```

## Publish to the DMS plugin registry

The DMS plugin registry is a curated GitHub repo at
[`AvengeMedia/dms-plugin-registry`](https://github.com/AvengeMedia/dms-plugin-registry).
`dms plugins browse` reads from it, and `dms plugins install <id>` clones the
listed repo. To make this plugin installable by other users:

1. **Push this repo to GitHub** (e.g. `github.com/darjss/dms-bar-usage`).

2. **Fork** [`AvengeMedia/dms-plugin-registry`](https://github.com/AvengeMedia/dms-plugin-registry).

3. **Add a registry entry** — create
   `plugins/darjs-ai-usage.json` in your fork:

   ```json
   {
       "id": "aiUsage",
       "name": "AI Usage",
       "capabilities": ["dankbar-widget"],
       "category": "monitoring",
       "repo": "https://github.com/darjss/dms-bar-usage",
       "author": "darjs",
       "description": "Shows Codex and Claude Code usage limits in the DankBar",
       "dependencies": ["sqlite3"],
       "compositors": ["any"],
       "distro": ["any"],
       "screenshot": "https://raw.githubusercontent.com/darjss/dms-bar-usage/master/screenshot.png"
   }
   ```

   The `id` and `name` **must exactly match** the fields in `plugin/plugin.json`.

4. **Validate** locally (from the registry repo checkout):

   ```bash
   pip install jinja2 requests
   python3 .github/generate.py --validate
   python3 .github/validate_links.py
   ```

5. **Open a PR** to `AvengeMedia/dms-plugin-registry` with the new JSON file.

Once merged, anyone can run `dms plugins install aiUsage`.

> See the registry's [CONTRIBUTING.md](https://github.com/AvengeMedia/dms-plugin-registry/blob/main/CONTRIBUTING.md) for the full, up-to-date guide.

### Before publishing

- Tag a release (`git tag v0.1.0`) so `dms plugins update aiUsage` has a ref to update to.
- Consider adding a `LICENSE` file.

## Tech stack

- **Go 1.23** — the `dms-ai-usage` data-fetching binary (stdlib only, no external deps)
- **QML / Qt Quick** — the bar widget and popout UI, running inside DankMaterialShell (Quickshell)
- **DankMaterialShell plugin API** — `PluginComponent`, `PluginSettings`, `SliderSetting`, `ToggleSetting`
