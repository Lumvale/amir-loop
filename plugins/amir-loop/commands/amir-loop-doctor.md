---
description: Diagnose why Amir Loop is or is not working on this machine
---

Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/amir-loop-doctor.sh"` from the current
project directory and show the output verbatim. Then, for each `FAIL:` line,
state the single concrete fix.

The doctor also checks the host-level Codex `notify` hook. This hook is separate
from Amir Loop's Stop hook, so a Codex notification failure can stop a session
even when Amir Loop itself is healthy. If the diagnostic reports a notify hook
that is failing on Windows, run:

```sh
bash "${CLAUDE_PLUGIN_ROOT}/scripts/amir-loop-doctor.sh" --disable-codex-notify
```

That explicit repair creates a timestamped backup beside `config.toml` and
removes only a single-line top-level `notify` setting. It refuses to edit
multi-line or ambiguous entries; inspect those manually instead.
