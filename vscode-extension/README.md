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

Which install the extension is actually talking to is not left implicit:
every time `Amir Loop: Doctor` runs, and once on the first successful status
refresh, the output channel gets a line naming the resolved `scripts/`
directory and *how* it was found - e.g. `Resolved from the
amirLoop.pluginPath setting: <configured path>/scripts` versus `Guessed at
~/.claude/plugins/amir-loop/scripts (global install guess)`. The same line
is appended to the status-bar tooltip, so it's visible without opening the
output channel at all. A stale checkout silently outranking the real active
install would otherwise be undetectable.

## Settings

| Setting | Description |
|---|---|
| `amirLoop.maxIterations` | Per-session turn cap passed to `--max-iterations` when starting a loop from `Amir Loop: Start`. Must be a positive whole number; an invalid value falls back to 1000 with a warning instead of being sent to `setup.sh` to fail there. |
| `amirLoop.pluginPath` | Path to the `plugins/amir-loop` directory (the one whose `scripts/` subfolder holds `amir-loop-status.sh`). Leave blank to autodetect. |

`amirLoop.pluginPath` autodetection checks, in order: the setting itself,
`CLAUDE_PLUGIN_ROOT` in the environment, `<workspace>/plugins/amir-loop`,
`<workspace>/.claude/plugins/amir-loop`, and a couple of plausible global
install locations under your home directory. This is a best-effort guess,
not a guarantee - if none of those match your install, set
`amirLoop.pluginPath` explicitly; the error message names the setting and
the kind of value it expects.

### Settings that intentionally do not exist here

Earlier drafts of this extension declared `amirLoop.days`, `amirLoop.until`,
and `amirLoop.off` alongside `amirLoop.maxIterations`. They were removed:
those three map to environment variables the **hook** reads at Stop time
(`AMIR_LOOP_DAYS`, `AMIR_LOOP_UNTIL`, `AMIR_LOOP_OFF` - see
`amir-loop-stop.sh`), and `amir-loop-setup.sh` (the only script this
extension can drive) accepts only `--max-iterations`, `--completion-promise`,
and `--cancel`. A VS Code extension has no channel to set the environment
that a hook the *host* invokes will see, so a `days`/`until`/`off` setting
here could never take effect - a user who set `amirLoop.days: 2` would
silently keep the hook's real default of 5. An absent setting is honest; a
setting that cannot work is not.

If you want to control these, set them as environment variables in whatever
process actually launches the hook - for example in the shell profile or
`.env` used by the terminal Claude Code (or VS Code's integrated terminal,
if that's what's invoking Claude Code) runs in, so the hook process inherits
them:

| Variable | Effect (read by the hook, not this extension) |
|---|---|
| `AMIR_LOOP_MAX` | Per-session turn cap (default 1000). Also settable per-loop via `Amir Loop: Start` / `amirLoop.maxIterations`, which takes precedence for that loop since it's passed explicitly as `--max-iterations`. |
| `AMIR_LOOP_DAYS` | Calendar window in days from the first arm (default 5). `0` means no deadline. |
| `AMIR_LOOP_UNTIL` | Absolute `YYYY-MM-DD` deadline; overrides `AMIR_LOOP_DAYS` if set. Unparseable values are treated as already expired. |
| `AMIR_LOOP_OFF` | Kill switch: `1` allows the Stop hook to end the loop immediately. (`Amir Loop: Cancel` achieves the same effect for the current project via `amir-loop-setup.sh --cancel`, which also writes the `.claude/amir-loop-off` file rather than relying on the environment.) |
| `AMIR_LOOP_AUTOARM` | `0` means "continue a loop someone already started, but never auto-arm a new one". |

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
