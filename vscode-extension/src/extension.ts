import * as vscode from 'vscode';
import * as path from 'path';
import * as fs from 'fs';
import * as os from 'os';
import { execFile } from 'child_process';
import { candidatePluginDirs, detectScriptsDir, parseStatus, renderStatusBar, PLUGIN_PATH_HELP } from './status';

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

function resolveScriptsDir(): string | undefined {
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
  name: string,
  args: string[],
  out: vscode.OutputChannel,
  onDone?: (stdout: string) => void,
): void {
  const dir = resolveScriptsDir();
  if (!dir) {
    vscode.window.showErrorMessage(PLUGIN_PATH_HELP);
    return;
  }
  execFile('bash', [path.join(dir, name), ...args], { cwd: root() }, (err, stdout, stderr) => {
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

export function activate(ctx: vscode.ExtensionContext): void {
  const out = vscode.window.createOutputChannel('Amir Loop');
  const item = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 100);
  item.command = 'amirLoop.doctor';
  ctx.subscriptions.push(item, out);

  const refresh = () => {
    const dir = resolveScriptsDir();
    if (!dir) {
      item.text = '$(question) Amir Loop';
      item.tooltip = PLUGIN_PATH_HELP;
      item.show();
      return;
    }
    execFile('bash', [path.join(dir, 'amir-loop-status.sh')], { cwd: root() }, (err, stdout) => {
      if (err) {
        item.text = '$(question) Amir Loop';
        item.tooltip = 'amir-loop-status.sh failed to run. Click to run doctor for details.';
        item.show();
        return;
      }
      const content = renderStatusBar(parseStatus(stdout));
      item.text = content.text;
      item.tooltip = content.tooltip;
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
    vscode.commands.registerCommand('amirLoop.doctor', () => runScript('amir-loop-doctor.sh', [], out)),
    vscode.commands.registerCommand('amirLoop.cancel', () => {
      runScript('amir-loop-setup.sh', ['--cancel'], out, () => refresh());
    }),
    vscode.commands.registerCommand('amirLoop.start', async () => {
      const prompt = await vscode.window.showInputBox({ prompt: 'What should the loop work on?' });
      if (!prompt) { return; }
      const cfg = vscode.workspace.getConfiguration('amirLoop');
      runScript(
        'amir-loop-setup.sh',
        ['--max-iterations', String(cfg.get<number>('maxIterations') ?? 1000), prompt],
        out,
        () => refresh(),
      );
    }),
  );
}

export function deactivate(): void { /* nothing to clean up */ }
