---
description: "Start an Amir Loop in this session with your own prompt"
argument-hint: "PROMPT [--max-iterations N] [--completion-promise TEXT]"
allowed-tools: ["Bash(bash \"${CLAUDE_PLUGIN_ROOT}/scripts/amir-loop-setup.sh\":*)"]
hide-from-slash-command-tool: "true"
---

# Amir Loop

Arm the loop with the prompt supplied below:

```!
bash "${CLAUDE_PLUGIN_ROOT}/scripts/amir-loop-setup.sh" "$ARGUMENTS"
```

Now work on that task. When you try to end your turn, the Stop hook feeds the SAME prompt back
to you for the next iteration, so you will see your own previous work in the files and in git
history and can build on it.

**CRITICAL RULE.** If a completion promise is set, you may output it ONLY when the statement is
completely and unequivocally TRUE. Do not output a false promise to escape the loop — not
because you are stuck, not because you think you should exit, not because the remaining work
looks hard. If you are blocked, say what is blocking you and keep working.

The loop also ends on its own when the iteration cap is reached, so there is never a need to
fake completion to get out.

To stop it deliberately, run `/amir-loop-cancel`.
