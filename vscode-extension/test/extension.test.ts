import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import {
  parseStatus,
  renderStatusBar,
  candidatePluginDirs,
  detectScriptsDir,
  describeResolvedScripts,
  validateMaxIterations,
  PLUGIN_PATH_HELP,
} from '../src/status';

// --- parseStatus -----------------------------------------------------------

test('parseStatus: idle', () => {
  const s = parseStatus('state: idle\n');
  assert.deepEqual(s, { state: 'idle' });
});

test('parseStatus: armed, full shape', () => {
  const stdout = [
    'state: armed',
    'iteration: 4 of 20',
    'promise: AMIR LOOP COMPLETE',
    'started: 2026-08-28T00:00:00Z',
    'principles: none',
    '',
  ].join('\n');
  const s = parseStatus(stdout);
  assert.deepEqual(s, {
    state: 'armed',
    iteration: 4,
    limit: 20,
    promise: 'AMIR LOOP COMPLETE',
    started: '2026-08-28T00:00:00Z',
  });
});

test('parseStatus: invalid, carries reason', () => {
  const stdout = [
    'state: invalid',
    'reason: iteration or max_iterations is not a number - the hook will discard this state file and allow the stop on the next turn',
    'principles: none',
    '',
  ].join('\n');
  const s = parseStatus(stdout);
  assert.equal(s.state, 'invalid');
  if (s.state === 'invalid') {
    assert.match(s.reason, /not a number/);
  }
});

test('parseStatus: extra lines (campaign, kill switch) do not break armed parsing', () => {
  const stdout = [
    'state: armed',
    'iteration: 1 of 1000',
    'promise: AMIR LOOP COMPLETE',
    'started: 2026-08-28T00:00:00Z',
    'campaign started: 2026-08-28T00:00:00Z',
    'kill switch: present',
    'principles: none',
    '',
  ].join('\n');
  const s = parseStatus(stdout);
  assert.equal(s.state, 'armed');
});

test('parseStatus: never salvages a malformed iteration into "armed" - the defect this parser exists to avoid', () => {
  // This is the exact shape amir-loop-status.sh emits instead of "armed" when
  // iteration/max_iterations fails the hook's own digits-only check - the
  // state file the hook is about to discard. A parser that recovers digits
  // out of "4abc" here would reintroduce that defect.
  const stdout = 'state: invalid\nreason: iteration or max_iterations is not a number\n';
  const s = parseStatus(stdout);
  assert.equal(s.state, 'invalid');
});

test('parseStatus: unrecognized output is "unknown", not misreported as idle/armed', () => {
  const s = parseStatus('something unexpected\n');
  assert.equal(s.state, 'unknown');
});

test('parseStatus: "armed" header without a parseable iteration line degrades to unknown, not a guess', () => {
  const s = parseStatus('state: armed\n');
  assert.equal(s.state, 'unknown');
});

// --- renderStatusBar ---------------------------------------------------------

test('renderStatusBar: idle reads as idle, not a problem', () => {
  const r = renderStatusBar({ state: 'idle' });
  assert.match(r.text, /idle/i);
});

test('renderStatusBar: armed shows iteration/limit', () => {
  const r = renderStatusBar({
    state: 'armed',
    iteration: 4,
    limit: 20,
    promise: 'AMIR LOOP COMPLETE',
    started: '2026-08-28T00:00:00Z',
  });
  assert.match(r.text, /4\/20/);
});

test('renderStatusBar: invalid reads as a problem, not idle and not armed', () => {
  const r = renderStatusBar({ state: 'invalid', reason: 'iteration or max_iterations is not a number' });
  assert.doesNotMatch(r.text.toLowerCase(), /idle/);
  assert.doesNotMatch(r.text.toLowerCase(), /armed/);
  assert.match(r.text, /(warning|invalid)/i);
  assert.match(r.tooltip, /not a number/);
});

test('renderStatusBar: unknown surfaces the raw output rather than hiding it', () => {
  const r = renderStatusBar({ state: 'unknown', raw: 'state: bogus\n' });
  assert.match(r.tooltip, /bogus/);
});

// --- candidatePluginDirs / detectScriptsDir / describeResolvedScripts ------

test('candidatePluginDirs: configured path takes priority, marked explicit', () => {
  const dirs = candidatePluginDirs({ configuredPluginPath: '/configured/amir-loop' });
  assert.equal(dirs[0].dir, '/configured/amir-loop');
  assert.equal(dirs[0].confidence, 'explicit');
  assert.match(dirs[0].label, /amirLoop\.pluginPath/);
});

test('candidatePluginDirs: CLAUDE_PLUGIN_ROOT is explicit; workspace/home fallbacks are guesses', () => {
  const dirs = candidatePluginDirs({
    envPluginRoot: '/env/amir-loop',
    workspaceRoot: '/ws',
    home: '/home/u',
  });
  const env = dirs.find((d) => d.dir === '/env/amir-loop');
  assert.equal(env?.confidence, 'explicit');
  assert.match(env!.label, /CLAUDE_PLUGIN_ROOT/);

  const workspaceGuesses = dirs.filter((d) => d.dir.startsWith('/ws'));
  assert.ok(workspaceGuesses.length >= 1);
  assert.ok(workspaceGuesses.every((d) => d.confidence === 'guess'));

  const homeGuesses = dirs.filter((d) => d.dir.startsWith('/home/u'));
  assert.ok(homeGuesses.length >= 1);
  assert.ok(homeGuesses.every((d) => d.confidence === 'guess'));
});

test('detectScriptsDir: picks the first candidate whose scripts/amir-loop-status.sh exists, and reports its label/confidence', () => {
  const dirs = candidatePluginDirs({ workspaceRoot: '/ws' });
  const wsPluginsDir = dirs.find((d) => d.dir.endsWith('plugins/amir-loop'))!.dir;
  const existing = new Set([`${wsPluginsDir}/scripts/amir-loop-status.sh`]);
  const found = detectScriptsDir(dirs, (p) => existing.has(p));
  assert.equal(found?.scriptsDir, `${wsPluginsDir}/scripts`);
  assert.equal(found?.confidence, 'guess');
});

test('detectScriptsDir: returns undefined when nothing matches', () => {
  const found = detectScriptsDir([{ dir: '/nope', confidence: 'guess', label: '/nope' }], () => false);
  assert.equal(found, undefined);
});

test('describeResolvedScripts: explicit sources read as "Resolved from", guesses read as "Guessed at"', () => {
  const explicit = describeResolvedScripts({ scriptsDir: '/a/scripts', confidence: 'explicit', label: 'the amirLoop.pluginPath setting' });
  assert.match(explicit, /^Resolved from the amirLoop\.pluginPath setting: \/a\/scripts$/);

  const guess = describeResolvedScripts({ scriptsDir: '/b/scripts', confidence: 'guess', label: '/b (global install guess)' });
  assert.match(guess, /^Guessed at \/b \(global install guess\): \/b\/scripts$/);
});

test('PLUGIN_PATH_HELP: tells the user exactly what to set and to what kind of value', () => {
  assert.match(PLUGIN_PATH_HELP, /amirLoop\.pluginPath/);
  assert.match(PLUGIN_PATH_HELP, /scripts/);
});

// --- validateMaxIterations ---------------------------------------------------

test('validateMaxIterations: accepts a positive whole number as-is', () => {
  const r = validateMaxIterations(20);
  assert.deepEqual(r, { value: 20 });
});

test('validateMaxIterations: rejects zero, negatives, non-integers, and non-numbers with a clear warning', () => {
  for (const bad of [0, -5, 1.5, 'abc', undefined, null]) {
    const r = validateMaxIterations(bad);
    assert.equal(r.value, 1000);
    assert.match(r.warning ?? '', /amirLoop\.maxIterations/);
    assert.match(r.warning ?? '', /positive whole number/);
  }
});
