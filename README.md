# DMS AI Usage

A [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) bar widget that shows **Codex** and **Claude Code** usage limits in the DankBar. Click the robot icon for a compact popout with per-window usage bars, reset countdowns, and credit balances.

## Features

- **Codex** — 5-hour window, weekly window, and credit balance
- **Claude Code** — 5-hour session, weekly (all models), model-specific weekly (Sonnet/Opus), and extra usage / spend credits
- Color-coded status bars (green / amber / red) based on usage percentage
- Auto-refresh with configurable interval (2–60 s)
- Toggle individual providers or the credits card from settings
- Two-column compact popout layout
- Reads tokens directly from local `~/.codex` and `~/.claude` dirs — no API keys to configure

## Requirements

| Dependency | Why |
|---|---|
| [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) >= 0.1 | Plugin host (Quickshell-based) |
| `go` >= 1.23 | Build the `dms-ai-usage` data binary |
| `sqlite3` | Codex fallback (reads `~/.codex/logs_2.sqlite`) |
| Codex CLI logged in (`~/.codex/auth.json`) | Codex usage via OAuth API |
| Claude Code logged in (`~/.claude/.credentials.json`) | Claude usage via OAuth API |

The widget shells out to `dms-ai-usage` on a timer; that binary fetches both providers in parallel and prints one JSON blob to stdout. If the live fetch fails, it falls back to a cached result in `~/.cache/dms-ai-usage/`.

## Install

### From the DMS plugin registry (once published)

```bash
dms plugins install aiUsage
dms restart
```

Or via DMS Settings → **Plugins** → **Browse** → search "AI Usage".

### Manual (this repo)

```bash
git clone https://github.com/darjs/dms-bar-usage.git
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
├── go.mod
├── Makefile             # build / install / install-plugin targets
└── plugin/
    ├── plugin.json          # DMS plugin manifest
    ├── AiUsageWidget.qml    # Bar widget + popout (composes UsageCard)
    ├── AiUsageSettings.qml  # Settings panel
    ├── UsageBar.qml         # Reusable progress bar component
    └── UsageCard.qml        # Reusable usage card component (icon, value, bar, footer)
```

## Publish to the DMS plugin registry

The DMS plugin registry is a curated GitHub repo at
[`AvengeMedia/dms-plugin-registry`](https://github.com/AvengeMedia/dms-plugin-registry).
`dms plugins browse` reads from it, and `dms plugins install <id>` clones the
listed repo. To make this plugin installable by other users:

1. **Push this repo to GitHub** (e.g. `github.com/darjs/dms-bar-usage`).

2. **Fork** [`AvengeMedia/dms-plugin-registry`](https://github.com/AvengeMedia/dms-plugin-registry).

3. **Add a registry entry** — create
   `plugins/darjs-ai-usage.json` in your fork:

   ```json
   {
       "id": "aiUsage",
       "name": "AI Usage",
       "capabilities": ["dankbar-widget"],
       "category": "monitoring",
       "repo": "https://github.com/darjs/dms-bar-usage",
       "author": "darjs",
       "description": "Shows Codex and Claude Code usage limits in the DankBar",
       "dependencies": ["sqlite3"],
       "compositors": ["any"],
       "distro": ["any"],
       "screenshot": "https://raw.githubusercontent.com/darjs/dms-bar-usage/main/screenshot.png"
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

- Add a `screenshot.png` at the repo root and reference it in the registry JSON.
- Tag a release (`git tag v0.1.0`) so `dms plugins update aiUsage` has a ref to update to.
- Consider adding a `LICENSE` file.
