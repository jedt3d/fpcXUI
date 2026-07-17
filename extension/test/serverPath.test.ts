import * as assert from 'node:assert/strict';
import { test } from 'node:test';
import * as path from 'node:path';

import {
  platformTarget,
  resolveServerPath,
  serverBinaryName,
} from '../src/serverPath';

test('platformTarget uses Node platform and architecture names', () => {
  assert.equal(platformTarget('darwin', 'arm64'), 'darwin-arm64');
  assert.equal(platformTarget('linux', 'x64'), 'linux-x64');
  assert.equal(platformTarget('win32', 'x64'), 'win32-x64');
});

test('platformTarget rejects unsupported targets', () => {
  assert.throws(() => platformTarget('aix', 'x64'), /platform 'aix'/);
  assert.throws(() => platformTarget('linux', 'riscv64'), /architecture 'riscv64'/);
});

test('serverBinaryName adds the executable suffix only on Windows', () => {
  assert.equal(serverBinaryName('win32'), 'fpcxui-ls.exe');
  assert.equal(serverBinaryName('darwin'), 'fpcxui-ls');
});

test('an absolute configured path has first priority', () => {
  const configured = path.resolve('/opt', 'fpcxui-ls');
  const resolution = resolveServerPath(
    '/workspace/extension',
    configured,
    'linux',
    'x64',
    (candidate) => candidate === configured,
  );

  assert.equal(resolution.executablePath, configured);
  assert.equal(resolution.source, 'configured');
  assert.equal(resolution.target, 'linux-x64');
});

test('a configured path must be absolute', () => {
  assert.throws(
    () => resolveServerPath('/workspace/extension', './fpcxui-ls', 'linux', 'x64'),
    /must be an absolute path/,
  );
});

test('the repository development binary precedes the packaged binary', () => {
  const extensionPath = path.resolve('/workspace', 'extension');
  const expected = path.resolve(
    '/workspace',
    'server',
    'bin',
    'darwin-arm64',
    'fpcxui-ls',
  );

  const resolution = resolveServerPath(
    extensionPath,
    '',
    'darwin',
    'arm64',
    () => true,
  );

  assert.equal(resolution.executablePath, expected);
  assert.equal(resolution.source, 'development');
});

test('the packaged binary is used when the development binary is absent', () => {
  const extensionPath = path.resolve('/workspace', 'extension');
  const expected = path.resolve(
    extensionPath,
    'server',
    'win32-x64',
    'fpcxui-ls.exe',
  );

  const resolution = resolveServerPath(
    extensionPath,
    '',
    'win32',
    'x64',
    (candidate) => candidate === expected,
  );

  assert.equal(resolution.executablePath, expected);
  assert.equal(resolution.source, 'packaged');
});

test('resolution fails clearly when no server binary exists', () => {
  assert.throws(
    () => resolveServerPath(
      '/workspace/extension',
      '',
      'linux',
      'x64',
      () => false,
    ),
    /No FPC XUI language-server executable is available for 'linux-x64'/,
  );
});
