import * as vscode from 'vscode';
import * as path from 'path';
import * as fs from 'fs';
import * as os from 'os';
import { execFile } from 'child_process';
import {
  candidatePluginDirs,
  detectScriptsDir,
  describeResolvedScripts,
  parseStatus,
  renderStatusBar,
  validateMaxIterations,
  PLUGIN_PATH_HELP,
  ResolvedScripts,
} from './status';

// Thin vscode glue only. All state interpretation (parsing amir-loop-status.sh
// output, rendering the status bar, choosing a plugin directory) lives in
// ./status.ts as pure functions so it can be unit-tested without the VS Code
// extension host. See status.ts for why the extension shells out to
// amir-loop-status.sh instead of reading .claude/amir-loop.local.md itself.

function root(): string | undefined {
  return vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
}

function statePath(): string | undefined {
  const r = root();
  return r ? path.join(r, '.claude', 'amir-loop.local.md') : undefined;
}

/**
 * Resolves which scripts directory the extension will use, and how it got
 * there (setting / CLAUDE_PLUGIN_ROOT / a workspace or global guess). Which
 * candidate wins is otherwise invisible - a stale checkout left in the
 * workspace could silently outrank the real active install - so callers
 * must surface the result via describeResolvedScripts(), not just use the
 * path.
 */
function resolvePlugin(): ResolvedScripts | undefined {
  const cfg = vscode.workspace.getConfiguration('amirLoop').get<string>('pluginPath') || '';
  const candidates = candidatePluginDirs({
    configuredPluginPath: cfg || undefined,
    envPluginRoot: process.env.CLAUDE_PLUGIN_ROOT,
    workspaceRoot: root(),
    home: os.homedir(),
  });
  return detectScriptsDir(candidates, (p) => fs.existsSync(p));
}

function runScript(
  resolved: ResolvedScripts,
  name: string,
  args: string[],
  out: vscode.OutputChannel,
  onDone?: (stdout: string) => void,
): void {
  execFile('bash', [path.join(resolved.scriptsDir, name), ...args], { cwd: root() }, (err, stdout, stderr) => {
    out.appendLine(stdout || '');
    if (stderr) { out.appendLine(stderr); }
    if (err) {
      vscode.window.showErrorMessage(`Amir Loop: ${name} failed - see output.`);
      out.show(true);
      return;
    }
    onDone?.(stdout);
  });
}

/** Resolves the plugin, or shows PLUGIN_PATH_HELP and returns undefined. */
function withResolved(out: vscode.OutputChannel, action: (resolved: ResolvedScripts) => void): void {
  const resolved = resolvePlugin();
  if (!resolved) {
    vscode.window.showErrorMessage(PLUGIN_PATH_HELP);
    return;
  }
  action(resolved);
}

export function activate(ctx: vscode.ExtensionContext): void {
  const out = vscode.window.createOutputChannel('Amir Loop');
  const item = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 100);
  item.command = 'amirLoop.doctor';
  ctx.subscriptions.push(item, out);

  // Announced once on the first successful status refresh, not on every
  // refresh - the file watcher can fire often and flooding the output
  // channel on every keystroke-adjacent change is its own problem.
  let announcedResolutionOnStatus = false;

  const refresh = () => {
    const resolved = resolvePlugin();
    if (!resolved) {
      item.text = '$(question) Amir Loop';
      item.tooltip = PLUGIN_PATH_HELP;
      item.show();
      return;
    }
    execFile('bash', [path.join(resolved.scriptsDir, 'amir-loop-status.sh')], { cwd: root() }, (err, stdout) => {
      if (err) {
        item.text = '$(question) Amir Loop';
        item.tooltip = `amir-loop-status.sh failed to run. Click to run doctor for details.\n${describeResolvedScripts(resolved)}`;
        item.show();
        return;
      }
      if (!announcedResolutionOnStatus) {
        out.appendLine(describeResolvedScripts(resolved));
        announcedResolutionOnStatus = true;
      }
      const content = renderStatusBar(parseStatus(stdout));
      item.text = content.text;
      // Always surfaced in the tooltip - discoverable without opening the
      // output channel - and it says *how* the scripts dir was found, since
      // "Resolved from the amirLoop.pluginPath setting" and "Guessed at
      // ~/.claude/plugins/..." warrant very different levels of trust.
      item.tooltip = `${content.tooltip}\n\n${describeResolvedScripts(resolved)}`;
      item.show();
    });
  };
  refresh();

  const p = statePath();
  if (p) {
    const watcher = vscode.workspace.createFileSystemWatcher(
      new vscode.RelativePattern(path.dirname(p), 'amir-loop.local.md'));
    watcher.onDidChange(refresh);
    watcher.onDidCreate(refresh);
    watcher.onDidDelete(refresh);
    ctx.subscriptions.push(watcher);
  }

  ctx.subscriptions.push(
    vscode.commands.registerCommand('amirLoop.doctor', () => withResolved(out, (resolved) => {
      // Doctor is explicitly user-invoked (not watcher-driven), so announcing
      // the resolution every time doesn't risk flooding the channel, and
      // doctor is exactly the moment a user wants to know which install is
      // in effect.
      out.appendLine(describeResolvedScripts(resolved));
      runScript(resolved, 'amir-loop-doctor.sh', [], out);
    })),
    vscode.commands.registerCommand('amirLoop.cancel', () => withResolved(out, (resolved) => {
      runScript(resolved, 'amir-loop-setup.sh', ['--cancel'], out, () => refresh());
    })),
    vscode.commands.registerCommand('amirLoop.start', async () => {
      const prompt = await vscode.window.showInputBox({ prompt: 'What should the loop work on?' });
      if (!prompt) { return; }
      const cfg = vscode.workspace.getConfiguration('amirLoop');
      const { value: maxIterations, warning } = validateMaxIterations(cfg.get<number>('maxIterations'));
      if (warning) { vscode.window.showWarningMessage(`Amir Loop: ${warning}`); }
      withResolved(out, (resolved) => {
        runScript(
          resolved,
          'amir-loop-setup.sh',
          ['--max-iterations', String(maxIterations), prompt],
          out,
          () => refresh(),
        );
      });
    }),
  );
}

export function deactivate(): void { /* nothing to clean up */ }
