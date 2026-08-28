import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import {
  parseStatus,
  renderStatusBar,
  candidatePluginDirs,
  detectScriptsDir,
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

// --- candidatePluginDirs / detectScriptsDir ---------------------------------

test('candidatePluginDirs: configured path takes priority and is included', () => {
  const dirs = candidatePluginDirs({ configuredPluginPath: '/configured/amir-loop' });
  assert.equal(dirs[0], '/configured/amir-loop');
});

test('candidatePluginDirs: falls back through env, workspace, and home candidates', () => {
  const dirs = candidatePluginDirs({
    envPluginRoot: '/env/amir-loop',
    workspaceRoot: '/ws',
    home: '/home/u',
  });
  assert.ok(dirs.some((d) => d === '/env/amir-loop'));
  assert.ok(dirs.some((d) => d.includes('/ws') && d.includes('plugins')));
  assert.ok(dirs.some((d) => d.includes('/home/u')));
});

test('detectScriptsDir: picks the first candidate whose scripts/amir-loop-status.sh exists', () => {
  const dirs = ['/nope', '/yes', '/also-yes'];
  const existing = new Set(['/yes/scripts/amir-loop-status.sh']);
  const found = detectScriptsDir(dirs, (p) => existing.has(p));
  assert.equal(found, '/yes/scripts');
});

test('detectScriptsDir: returns undefined when nothing matches', () => {
  const found = detectScriptsDir(['/nope'], () => false);
  assert.equal(found, undefined);
});

test('PLUGIN_PATH_HELP: tells the user exactly what to set and to what kind of value', () => {
  assert.match(PLUGIN_PATH_HELP, /amirLoop\.pluginPath/);
  assert.match(PLUGIN_PATH_HELP, /scripts/);
});
