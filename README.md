# amir-loop

Amir Loop is an auto-arming `Stop` hook that keeps an agent session going until the
work is genuinely **exhausted** — not until one task is done. It re-arms itself on
every stop, feeding the same prompt back so the agent picks up where it left off, and
it is bounded on two independent axes: a per-session turn cap and a calendar window.
The loop ends when either bound trips, or when the agent emits
`<promise>AMIR LOOP COMPLETE</promise>` after concluding there is truly nothing left
to advance. Its distinguishing property is that it runs in **Claude Code, VS Code
Copilot Chat, and Codex**: it emits the block decision in each host's own shape and
uses each host's stable final-message surface rather than assuming Claude Code's
transcript format.

## Install

### Claude Code

Add to `~/.claude/settings.json`:

```json
"extraKnownMarketplaces": {
  "lumvale": { "source": { "source": "git", "url": "https://github.com/Lumvale/amir-loop.git" } }
},
"enabledPlugins": { "amir-loop@lumvale": true }
```

Claude Code sessions launched from Claude Desktop pick this up automatically, since
they read the same `~/.claude/settings.json` plugin registry — no separate Desktop
setup is needed.

A native Claude Desktop **extension** is not possible for this tool. Desktop
extensions are MCPB bundles whose manifests expose `server`, `tools`, `prompts`, and
`user_config` — there is no hook surface in that format, so the Stop-hook mechanism
this plugin depends on cannot run there. The plugin path above is the only way to get
Amir Loop into a Desktop-launched session.

### VS Code Copilot Chat

Append the same git URL to `chat.plugins.marketplaces` in your VS Code settings.

### Codex

Add this repository as a Codex marketplace, then install the plugin:

```text
codex plugin marketplace add Lumvale/amir-loop
codex plugin add amir-loop@lumvale
```

Start a new task after installation, open `/hooks`, and trust the Amir Loop hook when
prompted. Codex hashes hook definitions, so a changed hook must be reviewed again before
it runs. The hook works in the Codex CLI, Codex IDE extension, and Codex desktop task
surfaces that run the local Codex lifecycle.

## Windows prerequisite

Claude and Copilot invoke `bash "${CLAUDE_PLUGIN_ROOT}/hooks/amir-loop-stop.sh"`, so
`bash` must resolve on PATH for those hosts. On Windows this means the Git for Windows
install directory's `bin` folder — typically under `Program Files\Git\bin` — needs to
be on PATH. Codex uses the bundled PowerShell launcher instead; it locates Git Bash next
to the active `git.exe`, avoiding accidental resolution to WSL's `bash.exe`. Run
`/amir-loop-doctor` to check the Claude/Copilot path precisely.

## Commands

| Command | What it does |
|---|---|
| `/amir-loop` | Arms a loop in the current session with your own prompt. The Stop hook then feeds that same prompt back on every turn until the loop ends. |
| `/amir-loop-cancel` | Cancels the active loop: removes the state file and writes a `.claude/amir-loop-off` kill switch, so the hook does not simply re-arm on the next turn. |
| `/amir-loop-status` | Shows the current loop state for this project (idle, armed with iteration/limit, or invalid) without mutating anything. |
| `/amir-loop-init` | Scaffolds a `.claude/amir-loop-principles.md` file from `templates/principles/`, if one does not already exist here. Never overwrites an existing principles file. |
| `/amir-loop-doctor` | Diagnoses why the loop is or is not working on this machine — bash resolution, vendored `jq`, and conflicting Stop-hook registrations — and states a concrete fix for each failure. |

## Configuration

Environment variables read by `hooks/amir-loop-stop.sh`:

| Variable | Default | Meaning |
|---|---|---|
| `AMIR_LOOP_MAX` | `1000` | Per-session turn cap. `0` or a non-numeric value is clamped to the default, because `0` would mean "never stop". |
| `AMIR_LOOP_DAYS` | `5` | Calendar window in days from the first arm, recorded in `.claude/.amir-loop-campaign`. `0` disables the deadline. A non-numeric value is treated as invalid and the hook allows the stop. |
| `AMIR_LOOP_UNTIL` | unset | Absolute date override for the deadline. Takes priority over `AMIR_LOOP_DAYS` when set. An unparseable value is treated as already expired. |
| `AMIR_LOOP_OFF` | `0` | Set to `1` as a global kill switch — the hook always allows the stop. |
| `AMIR_LOOP_AUTOARM` | `1` | Set to `0` to only continue a loop someone already started, never auto-arm a new one on a bare Stop. This is the posture used by the `~/.claude/settings.json` + `--claude-code` install shape, below. |

### Principles file

`.claude/amir-loop-principles.md` holds project-scoped standing orders (backlog to
pull from, merge authority, definition of done) that get appended to every armed
loop's prompt. It is resolved from the current working directory **upwards**, the
same way `.gitignore` or `.editorconfig` is — so a single file at the root of a fleet
of repositories covers every repo beneath it, without needing to be duplicated into
each one. Run `/amir-loop-init` to scaffold one from `templates/principles/` when none
exists yet; it will not touch a file that is already there.

## Conflicts

Only one Stop hook should be registered per host at a time.

`ralph-loop` registers its own Stop hook. If both `ralph-loop` and `amir-loop` are
enabled in the same host, both hooks fire on every stop and both increment their own
iteration counter — `/amir-loop-doctor` FAILs when it detects `ralph-loop` enabled
alongside this plugin. Disable one before using the other.

Separately, `~/.claude/settings.json` also supports installing this hook directly
(outside the plugin marketplace flow) using a `--claude-code` flag on the hook
command. That install shape is for scheduled routines — deliberately bounded,
discrete passes where the hook should never auto-arm a new loop and should stand down
entirely inside a VS Code session. It is mutually exclusive with the plugin install
above: use one or the other for a given host, not both.

## Lineage and credit

The state-file shape and the `{"decision":"block","reason":...}` block protocol come
from Anthropic's `ralph-wiggum` plugin. Amir Loop shares no code with it — it became
an independent implementation because `ralph-wiggum` greps the transcript for
`"role":"assistant"`, which is Claude Code's transcript format. VS Code Copilot Chat
writes a different shape entirely, so `ralph-wiggum` found no assistant messages,
took its "nothing to do" branch, and deleted its own state file on the very first arm,
every time, in that host. Amir Loop reads Claude and Copilot transcripts, while Codex's
adapter consumes the stable `last_assistant_message` Stop-hook field because Codex's
transcript format is explicitly not a stable interface. It emits each host's required
block shape, which is the reason it exists as its own plugin rather than a fork. This
history is documented in the header comment of
`plugins/amir-loop/hooks/amir-loop-stop.sh`.

## Development

Tests are written with [bats](https://github.com/bats-core/bats-core):

```
bats tests/
```

53 tests across 5 suites (`bounds`, `doctor`, `failopen`, `invariants`, `status`).
CI runs this suite on a 3-OS matrix (Ubuntu, macOS, Windows) on every push and pull
request.

`jq` is vendored as a static binary per platform under
`plugins/amir-loop/vendor/jq/`, so the hook does not depend on `jq` being installed.
Each vendored binary's checksum is recorded, verified against the checksums
**published upstream** by the jq project for that release (not merely recomputed
locally), in `plugins/amir-loop/vendor/jq/SOURCES.md`.
