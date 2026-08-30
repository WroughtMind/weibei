import test from 'node:test';
import assert from 'node:assert/strict';
import { chooseDownloadId, matchDownloadAssets, preferredDownloadIds } from './download-selection.mjs';

const assets = [
  { name: 'WeiBei-1.0.0-macOS-arm64.dmg' },
  { name: 'WeiBei-1.0.0-macOS-x86_64.dmg' },
  { name: 'WeiBei-1.0.0-Windows-x64.exe' }
];

test('安装包按系统与芯片匹配', () => {
  const matched = matchDownloadAssets(assets);
  assert.equal(chooseDownloadId(matched, preferredDownloadIds({ platform: 'macOS', architecture: 'arm' })), 'mac-arm64');
  assert.equal(chooseDownloadId(matched, preferredDownloadIds({ platform: 'macOS', architecture: 'x86' })), 'mac-intel');
  assert.equal(chooseDownloadId(matched, preferredDownloadIds({ platform: 'Windows', architecture: 'x86' })), 'windows-x64');
});

test('芯片未知时优先通用版', () => {
  const matched = matchDownloadAssets([{ name: 'WeiBei-1.0.0-macOS-universal.dmg' }]);
  assert.equal(chooseDownloadId(matched, preferredDownloadIds({ platform: 'MacIntel' })), 'mac-universal');
});

test('芯片未知且没有通用版时不猜测', () => {
  const matched = matchDownloadAssets(assets);
  assert.equal(chooseDownloadId(matched, preferredDownloadIds({ platform: 'MacIntel' })), 'mac-universal');
});
