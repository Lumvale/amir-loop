# amir-loop

A Claude Code plugin marketplace hosting the `amir-loop` plugin.

Amir Loop keeps an agent session going until the work is genuinely
exhausted, bounded by a per-session turn cap and a calendar window. It
works in both Claude Code and VS Code Copilot Chat.

## Layout

- `.claude-plugin/marketplace.json` — the `lumvale` marketplace manifest.
- `plugins/amir-loop/` — the plugin itself:
  - `.claude-plugin/plugin.json` — plugin manifest.
  - `commands/` — slash commands (`/loop`, `/cancel`).
  - `hooks/` — the Stop hook (`amir-loop-stop.sh`) and its `hooks.json`
    registration.
  - `scripts/` — setup script (`amir-loop-setup.sh`).

## Install

Add this repository as a marketplace and install the plugin:

```
/plugin marketplace add <path-or-url-to-this-repo>
/plugin install amir-loop@lumvale
```
