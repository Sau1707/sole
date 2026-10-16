import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

test('Sole files have a sun icon in light and dark themes', async () => {
  const root = new URL('../', import.meta.url);
  const manifest = JSON.parse(await readFile(new URL('package.json', root), 'utf8'));
  const language = manifest.contributes.languages.find(language => language.id === 'sole');
  assert.ok(language.extensions.includes('.sole'));
  for (const theme of ['light', 'dark']) {
    assert.equal(language.icon[theme], './icons/sole.svg');
    const icon = await readFile(new URL(language.icon[theme], root), 'utf8');
    assert.match(icon, /<svg\b/);
  }
});
