# Amir Loop (VS Code extension)

A thin control surface over the Amir Loop autonomy hook. It does not own any
state itself - it shells out to the same `amir-loop-*.sh` scripts the
Claude Code plugin uses, and reads their output.

## What it does

- Shows a status-bar item reflecting the current loop state in this
  workspace (`idle`, `armed N/limit`, or `invalid`), by running
  `amir-loop-status.sh` and parsing its stdout.
- `Amir Loop: Start` - prompts for what to work on, then runs
  `amir-loop-setup.sh --max-iterations <n> <prompt>`.
- `Amir Loop: Cancel` - runs `amir-loop-setup.sh --cancel`.
- `Amir Loop: Doctor` - runs `amir-loop-doctor.sh` and shows its output.
- Watches `.claude/amir-loop.local.md` in the first workspace folder and
  refreshes the status bar on change.

It never parses `.claude/amir-loop.local.md` itself. `amir-loop-status.sh`
is the single source of truth for what counts as "armed" versus "invalid" -
it mirrors the hook's own validation exactly, including discarding a state
file whose `iteration` or `max_iterations` isn't a whole number. A second,
looser parser in the extension could disagree with the hook.

## Settings

| Setting | Description |
|---|---|
| `amirLoop.maxIterations` | Per-session turn cap passed to `--max-iterations` on Start. |
| `amirLoop.days` | AMIR_LOOP_DAYS - calendar window from first arm. 0 = no deadline. |
| `amirLoop.until` | AMIR_LOOP_UNTIL - absolute YYYY-MM-DD deadline; overrides days. |
| `amirLoop.off` | AMIR_LOOP_OFF - kill switch. |
| `amirLoop.pluginPath` | Path to the `plugins/amir-loop` directory (the one whose `scripts/` subfolder holds `amir-loop-status.sh`). Leave blank to autodetect. |

`amirLoop.pluginPath` autodetection checks, in order: the setting itself,
`CLAUDE_PLUGIN_ROOT` in the environment, `<workspace>/plugins/amir-loop`,
`<workspace>/.claude/plugins/amir-loop`, and a couple of plausible global
install locations under your home directory. This is a best-effort guess,
not a guarantee - if none of those match your install, set
`amirLoop.pluginPath` explicitly; the error message names the setting and
the kind of value it expects.

## Development

```bash
npm install
npm run compile   # tsc -p ./
npm test          # compiles, then runs node --test against out/test
```

Status parsing and rendering live in `src/status.ts` as plain functions with
no `vscode` import, specifically so they can be unit-tested with
`node --test` without a VS Code extension host. `src/extension.ts` is glue
only: command registration, the status-bar item, and the file watcher.
