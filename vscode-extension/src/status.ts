import * as path from 'path';

// ---------------------------------------------------------------------------
// Pure logic, deliberately free of any `vscode` import. This lets it be
// unit-tested with plain `node --test` against the compiled output, without
// needing the VS Code extension host (which is the only place a `vscode`
// module actually resolves).
// ---------------------------------------------------------------------------

export type LoopStatus =
  | { state: 'idle' }
  | { state: 'armed'; iteration: number; limit: number; promise: string; started: string }
  | { state: 'invalid'; reason: string }
  | { state: 'unknown'; raw: string };

/**
 * Parses the stdout of amir-loop-status.sh into a LoopStatus.
 *
 * This is intentionally the ONLY place the extension interprets loop state.
 * It never reads .claude/amir-loop.local.md itself: amir-loop-status.sh
 * already mirrors the hook's own validation (see the case statements in
 * amir-loop-stop.sh) exactly, including the "iteration or max_iterations is
 * not a whole number" rejection that makes the hook discard the state file.
 * A second, looser parser here could disagree with the hook and report a
 * loop as armed when the hook has already treated it as over - which is
 * exactly the defect `state: invalid` exists to prevent. If the shape of
 * amir-loop-status.sh's output ever changes, update this parser, not the
 * other way around.
 */
export function parseStatus(stdout: string): LoopStatus {
  const lines = stdout.split(/\r?\n/);
  const stateLine = lines.find((l) => /^state:\s*/.test(l));
  const state = stateLine ? stateLine.replace(/^state:\s*/, '').trim() : undefined;

  const find = (re: RegExp): string | undefined => {
    for (const l of lines) {
      const m = re.exec(l);
      if (m) { return m[1]; }
    }
    return undefined;
  };

  if (state === 'idle') {
    return { state: 'idle' };
  }

  if (state === 'invalid') {
    const reason = find(/^reason:\s*(.*)$/) ?? 'unknown reason';
    return { state: 'invalid', reason };
  }

  if (state === 'armed') {
    const m = /^iteration:\s*(\d+)\s*of\s*(\d+)/m.exec(stdout);
    if (m) {
      const iteration = parseInt(m[1], 10);
      const limit = parseInt(m[2], 10);
      const promise = find(/^promise:\s*(.*)$/) ?? '';
      const started = find(/^started:\s*(.*)$/) ?? '';
      return { state: 'armed', iteration, limit, promise, started };
    }
    // "armed" without a parseable iteration line is a shape we don't
    // recognize - treat it like any other unrecognized output rather than
    // guessing at numbers.
    return { state: 'unknown', raw: stdout };
  }

  return { state: 'unknown', raw: stdout };
}

export interface StatusBarContent {
  text: string;
  tooltip: string;
}

/** Renders a LoopStatus into status-bar text/tooltip. Pure, no vscode API used. */
export function renderStatusBar(status: LoopStatus): StatusBarContent {
  switch (status.state) {
    case 'idle':
      return {
        text: '$(circle-outline) Amir Loop idle',
        tooltip: 'No loop armed in this workspace. Click to run doctor.',
      };
    case 'armed':
      return {
        text: `$(sync~spin) Amir Loop ${status.iteration}/${status.limit}`,
        tooltip: [
          'Amir Loop is armed.',
          `Promise: ${status.promise}`,
          `Started: ${status.started}`,
          'Click to run doctor.',
        ].join('\n'),
      };
    case 'invalid':
      return {
        text: '$(warning) Amir Loop invalid',
        tooltip: `Amir Loop state is invalid: ${status.reason}\nClick to run doctor.`,
      };
    case 'unknown':
      return {
        text: '$(question) Amir Loop unknown',
        tooltip: `amir-loop-status.sh returned output this extension does not recognize:\n${status.raw}\nClick to run doctor.`,
      };
  }
}

/**
 * Builds the ordered list of directories to check for scripts/amir-loop-status.sh.
 * Pure: takes every input explicitly so it can be unit-tested without mocking
 * `vscode`, `fs`, or `os`.
 *
 * Order of preference:
 *   1. The user's explicit amirLoop.pluginPath setting (if set).
 *   2. CLAUDE_PLUGIN_ROOT, set by Claude Code itself when it invokes plugin
 *      hooks - present if this VS Code process inherited it from a Claude
 *      Code-launched terminal/session.
 *   3. <workspace>/plugins/amir-loop - this repo's own dev layout, and the
 *      layout of any project that vendors the plugin the same way.
 *   4. <workspace>/.claude/plugins/amir-loop - a plausible per-project
 *      install location.
 *   5. ~/.claude/plugins/amir-loop and the marketplace-qualified path under
 *      ~/.claude/plugins/marketplaces/lumvale/amir-loop - plausible global
 *      install locations.
 *
 * This list is a best-effort guess, not a spec: Claude Code does not
 * document a single canonical install path across OS/version, so anything
 * beyond (1) and (2) is a guess about layouts we've actually seen. If none
 * of these exist, detectScriptsDir() returns undefined and the caller must
 * fall back to asking the user to set amirLoop.pluginPath explicitly.
 */
export function candidatePluginDirs(opts: {
  configuredPluginPath?: string;
  envPluginRoot?: string;
  workspaceRoot?: string;
  home?: string;
}): string[] {
  const candidates: string[] = [];
  if (opts.configuredPluginPath) { candidates.push(opts.configuredPluginPath); }
  if (opts.envPluginRoot) { candidates.push(opts.envPluginRoot); }
  if (opts.workspaceRoot) {
    candidates.push(path.join(opts.workspaceRoot, 'plugins', 'amir-loop'));
    candidates.push(path.join(opts.workspaceRoot, '.claude', 'plugins', 'amir-loop'));
  }
  if (opts.home) {
    candidates.push(path.join(opts.home, '.claude', 'plugins', 'amir-loop'));
    candidates.push(path.join(opts.home, '.claude', 'plugins', 'marketplaces', 'lumvale', 'amir-loop'));
  }
  return candidates;
}

/**
 * Picks the first candidate plugin directory whose scripts/amir-loop-status.sh
 * actually exists. `exists` is injected so this stays unit-testable without
 * touching the real filesystem.
 */
export function detectScriptsDir(
  candidates: string[],
  exists: (p: string) => boolean,
): string | undefined {
  for (const dir of candidates) {
    const scripts = path.join(dir, 'scripts');
    if (exists(path.join(scripts, 'amir-loop-status.sh'))) {
      return scripts;
    }
  }
  return undefined;
}

export const PLUGIN_PATH_HELP =
  'Amir Loop could not find its scripts. Set amirLoop.pluginPath in Settings to the ' +
  'directory containing plugins/amir-loop (i.e. the folder whose scripts/ subfolder ' +
  'holds amir-loop-status.sh) - for example the path to your amir-loop checkout\'s ' +
  '"plugins/amir-loop" directory, or wherever this plugin was installed.';
