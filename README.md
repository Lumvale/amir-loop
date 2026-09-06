# amir-loop

Amir Loop is an auto-arming `Stop` hook that keeps an agent session going until the
work is genuinely **exhausted** — not until one task is done. It re-arms itself on
every stop, feeding the same prompt back so the agent picks up where it left off, and
it is bounded on two independent axes: a per-session turn cap and a calendar window.
The loop ends when either bound trips, or after a two-phase machine-readable closeout.
A bare `<promise>AMIR LOOP COMPLETE</promise>` is never sufficient: phase one proves the
direct goal, pending delivery, dependencies and any dispatcher lease are terminal; phase two
confirms a fresh nonce. Exact-output user tests retain their literal-output exception. Its
distinguishing property is that it runs in **Claude Code, VS Code
Copilot Chat, Codex, and Google Antigravity**: it emits the continuation decision in each host's own shape and
uses each host's stable final-message surface rather than assuming Claude Code's
transcript format.

## Vision: governed general-purpose autonomy

Amir Loop is intended to grow toward general and eventually superhuman problem-solving
capability: autonomous execution, self-correction, self-healing, self-development, and
evidence-driven improvement across long-lived goals. This is a direction and an
engineering programme, not a claim that the present plugin is AGI or ASI.

The architectural invariant is governed recursive improvement. Hooks and agentic AI SDK
adapters may observe failures, choose a declared local or cloud inference route, retry or
repair integrations, and propose improvements. Deterministic policy must still decide
eligibility, authority, leases, budgets, routing constraints, evidence acceptance, and
rollback. The model may infer how to do authorized work; it may not grant itself a
permission, weaken a safety control, bypass authentication or tenancy, expose credentials,
or describe an unverified recovery as complete.

Portable routing, recovery, permission-diagnosis, and agent-SDK contracts belong in Amir
Loop so third-party users receive them. Fleet account ids, approved providers, cost limits,
tenancy, release authority, and architecture policy belong in companion capabilities such
as amir-loop-lumvaleos. A host-specific feature is incomplete until the same invariant is
available through every supported host adapter.

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

To upgrade, refresh the marketplace, remove the registered release, and install the newly
versioned release before restarting Codex:

```text
codex plugin marketplace upgrade lumvale
codex plugin remove amir-loop@lumvale
codex plugin add amir-loop@lumvale
```

Every behavior-changing `plugins/amir-loop` change must bump the Codex manifest version. On
Windows, a running Codex process can hold the installed hook open; publishing changed bytes under
the same version makes reinstall target that locked cache directory. A new version selects a new
cache path and keeps the supported remove/add flow deterministic.

For governed Lumvale fleet work, also install the optional companion and configure the
fleet root:

```text
codex plugin add amir-loop-lumvaleos@lumvale
```

The companion does not register a second Stop hook. It supplies the LumvaleOS policy
and configuration skill used by the core loop.

Start a new task after installation, open `/hooks`, and trust the Amir Loop hook when
prompted. Codex hashes hook definitions, so a changed hook must be reviewed again before
it runs. The hook works in the Codex CLI, Codex IDE extension, and Codex desktop task
surfaces that run the local Codex lifecycle.

### Google Antigravity

Copy `plugins/amir-loop` into the global Antigravity customization root as
`~/.gemini/config/plugins/amir-loop`, or register its parent directory in Antigravity's
`plugins.json`. The root `plugin.json` and `hooks.json` are Antigravity-native; its
PowerShell adapter translates camelCase lifecycle input and the `decision: continue`
Stop result to and from the shared loop implementation.

On Windows, restart Antigravity after installing or updating the plugin so it reloads
the hook definition. Existing conversations do not retroactively acquire a changed hook.

## Cross-host parity contract

Amir Loop features belong in the shared engine, not a host fork. Claude Code, VS Code,
Codex, and Antigravity all use the shared Bash engine for completion, cancellation,
dependency and runtime profiles, Bedrock retry classification, goal precedence, and
dispatcher closeout. Adapters may translate payload and decision shapes only.

| Capability | Claude Code | VS Code | Codex | Antigravity |
|---|---|---|---|---|
| Two-phase completion and false-promise rejection | shared Stop | shared Stop | shared Stop with stable final-message field | shared Stop through native adapter |
| Exact-output user contract | UserPromptSubmit | UserPromptSubmit | UserPromptSubmit | latest user message derived during native PreInvocation |
| Startup reconciliation, single-IDE claim, and prompt injection | SessionStart | SessionStart | SessionStart | idempotent native PreInvocation |
| Source/test/environment/learning observations | governed PostToolUse | governed PostToolUse | governed PostToolUse | native matcher groups translated to redacted shared observations |
| Prospective action attribution | shared pre/post-tool ledger | shared pre/post-tool ledger | stable turn plus shared pre/post-tool ledger | native metadata translated to the shared ledger |
| Runtime/dependency profiles and Bedrock retry policy | shared | shared | shared | shared |
| Cancellation, bounds, stale-state recovery | shared | shared | shared | shared |

Antigravity does not expose SessionStart or UserPromptSubmit; its documented
PreInvocation payload includes the workspace, conversation, and transcript, which is
enough to provide the same behavior without polling or using an unsupported event name.
Its PostToolUse payload intentionally omits tool arguments, so the adapter classifies
failed test commands only from redacted failure metadata and never copies command output
into an event.

### Action provenance and its evidence boundary

The shared host hook appends redacted pre/post-tool observations to
`.lumvaleos/agent-actions.jsonl`. Each record carries the timestamp, host surface, session and
turn identifiers, model when the host exposes it, its `model_identity_source`, tool name, a
SHA-256 command fingerprint,
path-shaped arguments, MSYS path semantics, outcome, and any guard decision present in the host
payload. Raw prompts, commands, outputs, and credentials are not stored.

`amir-loop-doctor` summarizes the ledger by host and model and highlights drive-root
materialization risks. Missing identity stays `unknown`: `host-payload` proves the identifier was
observed, while `not-exposed` proves the supported host fields were absent. Expected non-exposure
is informational; ambiguous legacy or contradictory rows remain warnings. The ledger supports
deterministic attribution only for actions observed after installation, and it never manufactures
retrospective proof. Hooks are prevention and evidence controls, not an operating-system security boundary;
restrict writable roots with the host sandbox or OS access controls when writes must be impossible.

Agents and integrations can request a compact, stable diagnostic contract with
`plugins/amir-loop/scripts/amir-loop-doctor.sh --json` or the Windows-native
`amir-loop-doctor.ps1 -Json`. The schema reports ordered check codes, severities, actionable
remediation, summary counts, and the resolved plugin version/root. Human output remains the
default; JSON mode is read-only and does not enable repair actions.

Every behavioral change must add or update regression coverage for all four hosts. A
host-specific optimization is acceptable only when the shared invariant remains tested
through every other host's native adapter or transcript shape.

## Windows prerequisite

Claude and Copilot invoke `bash "${CLAUDE_PLUGIN_ROOT}/hooks/amir-loop-stop.sh"`, so
`bash` must resolve on PATH for those hosts. On Windows this means the Git for Windows
install directory's `bin` folder — typically under `Program Files\Git\bin` — needs to
be on PATH, **ahead of `C:\Windows\System32`**. Codex uses the bundled PowerShell launcher
instead; it locates Git Bash next to the active `git.exe`, avoiding accidental resolution to
WSL's `bash.exe`. Run `/amir-loop-doctor` to check the Claude/Copilot path precisely.

The packaged Codex doctor skill uses `plugins/amir-loop/scripts/amir-loop-doctor.ps1` on
Windows. That entrypoint selects Git for Windows Bash explicitly and refuses the System32/WSL
shim, so diagnosis still starts when the host's PATH is ordered incorrectly. The
`amir-loop-lumvaleos` companion likewise provides `configure-lumvaleos.ps1`; configuration does
not need a shell merely to write its JSON policy. Restart the host or begin a new agent session
after changing plugin policy or installation because hosts cache skills, MCP configuration and
hook definitions.

When the companion is installed, session start and user-prompt activity wake LumvaleOS's central
automation reconciler. These are opportunistic signals, not timers: LumvaleOS finds every overdue
Workspace job, checkpoints successful work, and uses one Workspace-global lease so concurrent
agent sessions cannot run a second instance. No cron, Windows Task Scheduler, or GitHub scheduled
workflow is required for local agentic work.

The adapter adopts `WORKSPACE_ROOT`, `WORKSPACE_LOCAL`, and `WORKSPACE_NAME` from the host's
LumvaleOS registration before activation. Opening Codex, Claude Code, or Antigravity therefore
cannot silently claim schedules from a different ambient Workspace.

> **The ordering is not optional, and appending is the common mistake.** `System32` ships its
> own `bash.exe` (WSL) and normally precedes anything you add, so *appending* `Git\bin` leaves
> `bash` resolving to WSL:
>
> ```console
> # after appending  C:\Program Files\Git\bin
> > (Get-Command bash -All | Select-Object -First 1).Source
> C:\Windows\system32\bash.exe
> # after prepending C:\Program Files\Git\bin
> C:\Program Files\Git\bin\bash.exe
> ```
>
> Under WSL the hooks cannot work at all: WSL strips variable references from a `-c` string
> before bash parses it, so the plugin root is never resolvable. If PATH order is not something
> you can change, run `plugins/amir-loop/scripts/patch-windows-hooks.sh` to point the launchers at Git Bash
> explicitly. See [docs/windows-wsl-hooks.md](docs/windows-wsl-hooks.md) and
> [#30](https://github.com/Lumvale/amir-loop/issues/30).

## Commands

| Command | What it does |
|---|---|
| `/amir-loop` | Arms a loop in the current session with your own prompt. The Stop hook then feeds that same prompt back on every turn until the loop ends. |
| `/amir-loop-cancel` | Cancels active loops in the project: removes their session-scoped state files and writes a `.claude/amir-loop-off` kill switch, so the hook does not simply re-arm on the next turn. |
| `/amir-loop-status` | Shows the current loop state for this project (idle, armed with iteration/limit, or invalid) without mutating anything. The underlying script also accepts `--json` for a schema-versioned aggregate and per-session status contract. |
| `/amir-loop-init` | Scaffolds a `.claude/amir-loop-principles.md` file from `templates/principles/`, if one does not already exist here. Never overwrites an existing principles file. |
| `/amir-loop-doctor` | Diagnoses why the loop is or is not working on this machine — bash resolution, vendored `jq`, conflicting Stop-hook registrations, and stale copies across supported hosts — and states a concrete fix for each failure. |

## Configuration

Environment variables read by `hooks/amir-loop-stop.sh`:

| Variable | Default | Meaning |
|---|---|---|
| `AMIR_LOOP_MAX` | `1000` | Per-session turn cap. `0` or a non-numeric value is clamped to the default, because `0` would mean "never stop". |
| `AMIR_LOOP_DAYS` | `5` | Calendar window in days from the first arm, recorded in `.claude/.amir-loop-campaign`. `0` disables the deadline. A non-numeric value is treated as invalid and the hook allows the stop. |
| `AMIR_LOOP_UNTIL` | unset | Absolute date override for the deadline. Takes priority over `AMIR_LOOP_DAYS` when set. An unparseable value is treated as already expired. |
| `AMIR_LOOP_OFF` | `0` | Set to `1` as a global kill switch — the hook always allows the stop. |
| `AMIR_LOOP_AUTOARM` | `1` | Set to `0` to only continue a loop someone already started, never auto-arm a new one on a bare Stop. This is the posture used by the `~/.claude/settings.json` + `--claude-code` install shape, below. |
| `AMIR_LOOP_PROVIDER` | unset | Optional provider activation signal for hosts that do not expose one in hook payloads. Set to `bedrock` only when the host itself is already configured to perform inference through Amazon Bedrock. |
| `AMIR_LOOP_WORKSPACE_ROOT` | unset | Explicit LumvaleOS Workspace whose rendered `.lumvaleos/amir-loop-principles.md` governs this run. `WORKSPACE_ROOT` is the shared fallback. The root must contain `workspace.yaml`. |

### Principles file

`.claude/amir-loop-principles.md` holds project-scoped standing orders (backlog to
pull from, merge authority, definition of done) that get appended to every armed
loop's prompt as candidate policy, not automatic scope. It is resolved from the current working directory **upwards**, the
same way `.gitignore` or `.editorconfig` is — so a single file at the root of a fleet
of repositories covers every repo beneath it, without needing to be duplicated into
each one. Run `/amir-loop-init` to scaffold one from `templates/principles/` when none
exists yet; it will not touch a file that is already there.

Each standing instruction, including actions described by dependency/runtime briefs, is
independently gated. Universal safety, authority, confidentiality, data-integrity,
required dependency health, and working-copy placement constraints always govern
execution. Domain-specific instructions apply only when the active workspace enables
their domain, the current goal is materially relevant, their trigger is satisfied, the
required environment and capabilities are available, execution does not expand or
pre-empt the user's goal, and safety and authority requirements are met. Inheritance
from an ancestor directory is not proof of domain relevance.

A required dependency's health preflight remains mandatory. Backlog, dispatcher, routine,
and playbook actions exposed by that dependency do not inherit that mandatory status; they
must pass the same workspace and current-goal applicability test.

Completing the direct goal does not unlock unrelated standing-order backlog, routine,
or playbook work. Fallback selection is eligible only when the direct request itself
authorises ongoing or backlog selection in that domain; otherwise the loop closes out.

When `AMIR_LOOP_WORKSPACE_ROOT` or `WORKSPACE_ROOT` selects a valid LumvaleOS Workspace, its
rendered `.lumvaleos/amir-loop-principles.md` takes precedence. Amir Loop does not continue an
ancestor search outside that Workspace. The rendered header records the Workspace id and effective
policy hash in the session brief, while LumvaleOS re-evaluates capability authorization live on
each server call. See [Workspace policy integration](docs/workspace-policy-integration.md).

Loop state is isolated per host session as `.claude/amir-loop.<session>.local.md`.
The worktree is also protected by an atomic `.claude/.amir-loop-worktree-claim/` directory.
Campaign dispatchers must run `amir-loop-worktree-claim.sh acquire WORKTREE SESSION_ID` before
assigning, resetting, or rebuilding a worktree, and proceed only on exit 0. Exit 73 is a live or
unreadable collision and must select another worktree. Hooks refresh the owning claim on activity;
well-formed claims older than `AMIR_LOOP_CLAIM_STALE_SECONDS` (seven days by default) may be
atomically reclaimed, while malformed claims always fail closed.
`amir-loop-status.sh --json` exposes the claim owner, heartbeat age, threshold, and
`unclaimed|live|stale|invalid` classification; `amir-loop-doctor.sh` reports the same safety
state so automation does not need to parse raw claim files.
This prevents two chats rooted in the same workspace from inheriting or overwriting
each other's goal. A manually armed loop is first written as `amir-loop.pending.local.md`
and claimed by the next Stop event in that chat. Older project-wide
`amir-loop.local.md` files are deliberately ignored by current hooks.

### Runtime dependency policy

Projects may define `.claude/amir-loop-dependencies.json`, resolved from the working
directory upwards just like the principles file. Each dependency has an `id`, `kind`,
and policy: `required`, `preferred`, or `off`. Required dependencies fail closed before
substantive work; preferred dependencies explicitly degrade once; off dependencies are
ignored. A required dependency failure uses
`<amir-loop-blocked>DEPENDENCY_ID</amir-loop-blocked>` to pause the current turn without
declaring completion or discarding the session goal. A later human turn resumes it.

The core is vendor-neutral. `amir-loop-lumvaleos` supplies Lumvale's opinionated profile:
LumvaleOS is required for governed knowledge, flows, backlog selection, and evidence, while
ordinary shell, repository, build, test, review, and git operations remain native tools.

```json
{
  "version": 1,
  "dependencies": [{
    "id": "example-mcp",
    "kind": "mcp",
    "policy": "preferred",
    "preflight": "Call its status capability once.",
    "repair": "Enable the MCP and restart the host."
  }]
}
```

### External blocker suspension

A direct goal that only a person or external state can advance uses a separate, fail-closed
protocol. Emit one compact JSON object and no completion promise:

```text
<amir-loop-external-blocker>{"version":1,"blocker_kind":"owner-only","blocker_id":"github-app-permission-50","exact_human_action":"Set the GitHub App Actions permission to Read and write and approve the installation update.","evidence_uri":"https://github.com/Lumvale/amir-loop/issues/50","resume_condition":"When the installation permission read-back reports Actions write access.","exhausted_agent_side_alternatives":["Verified the current permission through the GitHub API.","Confirmed the app owner must approve this permission change."],"pending_ci":false,"remaining_agent_actionable_work":false,"actionable_items":[]}</amir-loop-external-blocker>
```

The Stop hook requires every field, accepts only `owner-only` or `external-state`, requires a
concrete human action, an HTTPS evidence URI, a concrete `when`/`after`/`once` resume condition,
and at least one exhausted agent-side alternative. `pending_ci` must be false,
`remaining_agent_actionable_work` must be false, and `actionable_items` must be empty. Pending
scheduled default-branch CI is handled by durable asynchronous reconciliation instead. Missing or vague fields and
remaining work are rejected with a deterministic reason. A valid marker persists the blocker
evidence, suppresses Stop re-arming for that turn without declaring completion, and leaves the
session state intact so the next user or externally triggered turn resumes the same goal.

### Amazon Bedrock

Amir Loop does not proxy or invoke a model itself; it preserves the host's continuation lifecycle.
Bedrock support is therefore native provider governance rather than a second inference client. Copy
`templates/runtime/bedrock.json` to `.claude/amir-loop-runtime.json`, choose the deployment's region
and pinned model or application inference-profile ARN, and keep credentials out of that file. The
profile is resolved from the working directory upwards, included in manually and automatically armed
briefs, checked by `/amir-loop-doctor`, and treated as a required preflight when `required` is true.

For Claude Code, follow the [official Bedrock deployment guide](https://code.claude.com/docs/en/amazon-bedrock)
and configure the host with `CLAUDE_CODE_USE_BEDROCK=1`; it uses the AWS SDK default
credential chain (or a Bedrock bearer token) and resolves `AWS_REGION`, `AWS_DEFAULT_REGION`, then the
active AWS profile. Pin `ANTHROPIC_MODEL` or the default model variables rather than relying on an
alias that may change. Other hosts can set `AMIR_LOOP_PROVIDER=bedrock` after their own Bedrock
adapter is active. Amir Loop never reads, logs, copies, or validates secret values and never makes a
network call merely to process a Stop event.

Bedrock throttling, service-unavailable, stream, model-timeout, and credential-chain timeout signals
use the same bounded retry budget as other transient provider failures. Access-denied and validation
errors are intentionally not retried: those require configuration repair, not a retry storm.

Each primary goal includes one bounded related-work reconciliation. The loop searches the
relevant issues, boards, and open pull requests for matching identifiers, symptoms, component,
root cause, and outcome. It may consolidate confirmed duplicates and co-resolvable work covered
by the same fix, but it must preserve merely similar items whose scope or acceptance criteria
differ. It reconciles links and statuses again before completion without turning that search into
general backlog work.

After a host compacts or summarises a long conversation, every continuation explicitly tells
the agent to re-read its session-scoped state and reconstruct the direct primary goal from
verified evidence. A summary's suggested next step cannot silently promote fallback backlog
work over unfinished direct work.

Per ADR-067, ordinary pull requests do not wait for runner-backed build or test CI. The agent runs
the applicable local/static checks, self-reviews the exact head, pushes, creates or updates the pull
request, and merges that reviewed head automatically. It enables GitHub auto-merge when the
repository plan supports it; otherwise it may immediately API-merge the reread exact head without
adding an Actions workflow, making the repository public, or widening App permissions. A changed
head must be revalidated.

Hourly, nightly and weekly default-branch CI is asynchronous evidence for promotion, not a PR merge
gate. The build/test authority is `Lumvale/lumvale-infra` **Fleet Build** (stable workflow file
`fleet-scheduler.yml`), which selects changed applicable repositories across both organizations and
drains one concurrency-2 queue on one ephemeral runner. Durable reconciliation records the merged
SHA, tier, terminal criteria and follow-up actions. It reads Fleet Build's per-repository result,
checkpoint and exact-SHA receipt; it never dispatches the product's old workflow after merge.
A repository absent from a run is UNKNOWN until applicability, elapsed tier window, current HEAD and
last successful checkpoint are reconciled.
it rejects stale evidence and prevents release, versioning or deployment until a relevant stable
scheduled build succeeds. An explicitly approved pre-merge exception remains fail-closed, but an
existing workflow or required context is not itself approval. Notifications are reserved for
terminal or materially actionable changes.

The scheduled fleet run is a bounded singleton. If it is healthy and still draining its
concurrency-2 queue when the next hour arrives, the clock suppresses a replacement instead of
cancelling or overlapping it. Each repository has a shorter timeout and every success is
checkpointed immediately, so a later natural tick resumes only the uncheckpointed tail. This rule
is specific to scheduled fleet work: superseded PR/head workflows may still cancel while Story C
removes that older runner-backed topology.

### Context-driven events and reconciliation

Supported host lifecycle hooks append redacted, workspace-scoped CloudEvents for
`session.started`, `source.changed`, `test.failed`, `environment.reachable`, and
`learning.discovered`. Startup adds a deduplicated sparse `heartbeat.reconcile` fact at most once
per configured heartbeat bucket. GitHub, CI and deployment adapters produce PR, deployment and
incident facts. Emitters are best-effort and cannot complete or corrupt the direct goal.

LumvaleOS owns event deduplication, deterministic due-time calculation, occurrence records,
leases, stale-claim recovery and evidence acceptance. Startup may reconcile while a direct goal is
active but does not lease fallback work; the dispatcher is consulted once at the goal-safe fallback
boundary. If every IDE or executor is closed, context-driven work waits until one reopens unless a
separately authorised deadline scheduler emits an idempotent due event. The external scheduler never
executes the prompt itself.

## Host boundaries

A Stop hook can recover a transport failure only when the host actually invokes Stop and
includes the failure in the hook payload or final message. Some VS Code Copilot request errors
(including observed `ERR_EMPTY_RESPONSE` failures) abort before Stop receives the error; no
plugin can retry an event it was never called for. Amir Loop recognises common transient codes
when they are delivered, retries them within `AMIR_LOOP_RETRY_MAX`, and otherwise fails open so
the host can expose its own **Try Again** action.

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

110 tests across 9 suites (`antigravity`, `bounds`, `dependencies`, `doctor`, `failopen`,
`invariants`, `parity`, `setup-args`, `status`).
The repository's scheduled default-branch tier runs this suite. Pull requests rely on exact-head
local/static evidence and self-review per ADR-067; they do not allocate the four-runner matrix.

`jq` is vendored as a static binary per platform under
`plugins/amir-loop/vendor/jq/`, so the hook does not depend on `jq` being installed.
Each vendored binary's checksum is recorded, verified against the checksums
**published upstream** by the jq project for that release (not merely recomputed
locally), in `plugins/amir-loop/vendor/jq/SOURCES.md`.
