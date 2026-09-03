# Windows: hooks do nothing, and say `plugin root unresolved`

If a hook prints

```
amir-loop: plugin root unresolved - a bare bash on Windows is WSL which strips variable
references from -c strings - name Git Bash explicitly - see Lumvale/amir-loop issue 30
```

or, on a build predating that message, dies with

```
/bin/bash: -c: line 1: syntax error near unexpected token `[A-Za-z]:*'
```

then the host is running the launcher under **WSL**, not Git Bash, and no hook can work until
that is changed. Run the setup script below.

## The fix

```bash
plugins/amir-loop/scripts/patch-windows-hooks.sh --check <path-to>/hooks/hooks.json   # is it needed?
plugins/amir-loop/scripts/patch-windows-hooks.sh         <path-to>/hooks/hooks.json   # apply
```

Then **reload the host window**. Hook definitions are read into memory at plugin-load time, so
the change does not take effect until then, and the old message reappears meanwhile — which reads
as "the fix failed" when the fix was simply not loaded.

The script is idempotent, writes a one-time backup beside the target, and preserves each hook's
own `--observe=` event.

> The file it patches is **vendored**: a plugin update overwrites it and the problem returns. That
> is why this is a script with a `--check` mode rather than a documented hand-edit. Re-run it after
> an update.

## Why the launcher cannot fix this itself

The shipped launchers are `bash -lc '...'`. On Windows, `bash` on PATH resolves to the `bash.exe`
in `System32` — **WSL** — ahead of Git Bash, which is not in the resolution order at all. WSL's
Windows-side invocation layer then **strips every `$NAME`/`${NAME}` from the `-c` string before
bash parses it**, so `CLAUDE_PLUGIN_ROOT` and its fallbacks are gone before any shell logic runs.

The decisive test, which separates "stripped before bash" from "expanded to empty" — these look
identical otherwise:

```console
PS> & "$env:SystemRoot\System32\bash.exe" -lc 'r=HELLO; echo SAW:$r'
SAW:
PS> & "$env:ProgramFiles\Git\bin\bash.exe" -lc 'r=HELLO; echo SAW:$r'
SAW:HELLO
```

`r` is assigned `HELLO` and still comes back empty, which is impossible if `$r` had reached bash.

`command` is a single string executed by whatever shell the host chooses, and the plugin does not
get to choose it. Every alternative is a dead end:

| Approach | Why it fails |
|---|---|
| Defensive quoting (`[ x$r != x ]`, `case x$r in`) | The variables are gone before bash parses. It only converts the syntax error into a silent skip. |
| A relative script path | Hosts differ. Claude Code and VS Code run hooks with `cwd` = the **project**, so a relative path misses. Only the Antigravity manifest's host uses `cwd` = plugin root. |
| Detect WSL and re-exec Git Bash | WSL cannot exec a Windows binary: `cannot execute binary file: Exec format error`. |
| `${CLAUDE_PLUGIN_ROOT}` braced form | Expanded textually by the host, putting raw Windows backslashes back into the command. `tests/invariants.bats` asserts against it. |
| A `node` launcher | Works, but adds the core's **first** hard runtime dependency. This plugin vendors `jq` specifically to avoid assuming host tooling. |
| `sh -c` | Windows has no `sh.exe` in `System32`, and Git's lives in the Git install's `bin`, usually not on PATH. |

So the launcher's job is to **fail open and say why** — which it does — and the host-specific
interpreter choice belongs in this opt-in setup step.

## What the patched command looks like

```
<git-bash-short-path> <plugin-root-short-path>/hooks/amir-loop-stop.sh --observe=post-tool
```

Two properties matter and are easy to lose when hand-editing:

- **No variables.** Nothing for WSL to strip, and nothing for a host to expand into backslashes.
- **No spaces.** Some hosts run hook commands through PowerShell, where a *leading quoted path* is
  a **parser** error (`Unexpected token`), not a runtime one — so the path cannot simply be quoted.
  `cygpath -ms` yields the 8.3 short form, in which `Program Files` becomes an eight-character
  name ending in `~1`, so the whole path is space-free and needs no quoting in either PowerShell
  or bash. The script does this for you.

## Note for CI

GitHub's `windows-latest` runners have **no WSL**, so `bash` there is Git Bash and the shipped
launcher passes. CI cannot reproduce this class of failure — it is specific to Windows hosts that
have WSL installed.

## A note on absolute paths in this repo

CI forbids literal drive-letter paths in committed `*.json`, `*.sh`, `*.md` and `*.ts` files
(`Assert no absolute paths` in `.github/workflows/test.yml`). That is why this page uses
`$env:SystemRoot` / `$env:ProgramFiles` and placeholders instead of pasting real paths, and why
the setup script derives every path at runtime rather than hard-coding one.
