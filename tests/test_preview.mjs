import { test } from 'node:test';
import assert from 'node:assert/strict';
import { decodeStore, matches } from '../macos/preview/search.mjs';

const links = decodeStore({ version: 1, links: [
  { alias: 'portfolio', url: 'https://www.figma.com/files', tags: ['design'], note: 'Interaction prototypes' },
  { alias: 'github', url: 'https://github.com/arjun', tags: ['dev', 'identity', 'dev'] },
  { alias: 'apple-docs', url: 'https://developer.apple.com/documentation', tags: ['dev'] },
] });

test('keyboard search ranks aliases and accepts nonconsecutive letters', () => {
  assert.deepEqual(matches(links, '  GH  ').map(link => link.alias), ['github']);
  assert.deepEqual(matches(links, 'git').map(link => link.alias), ['github']);
  const withAnotherGitHubURL = [...links, { alias: 'source', url: 'https://github.com/swiftlang/swift', tags: [], note: '' }];
  assert.deepEqual(matches(withAnotherGitHubURL, 'gh').map(link => link.alias), ['github', 'source']);
  assert.deepEqual(matches(links).map(link => link.alias), ['apple-docs', 'github', 'portfolio']);
});

test('search finds URL, tags and notes and combines with the current tag', () => {
  assert.deepEqual(matches(links, 'prototypes').map(link => link.alias), ['portfolio']);
  assert.deepEqual(matches(links, 'figma').map(link => link.alias), ['portfolio']);
  assert.deepEqual(matches(links, 'identity').map(link => link.alias), ['github']);
  assert.deepEqual(matches(links, '', 'dev').map(link => link.alias), ['apple-docs', 'github']);
  assert.deepEqual(matches(links, 'github', 'design'), []);
  assert.deepEqual(matches(links, 'zzzzzz'), []);
});

test('opening a store tolerates CLI metadata and normalizes optional fields', () => {
  assert.deepEqual(decodeStore({ links: null }), []);
  assert.deepEqual(decodeStore({ version: 1, links: [{ alias: '', url: 'https://github.com' }] }), []);
  assert.deepEqual(links[1].tags, ['dev', 'identity']);
  assert.equal(links[1].note, '');
  const store = { version: 1, links: [{ alias: 'docs', url: 'https://swift.org', copy_count: 4, last_copied: '2026-10-30T10:00:00Z', created_at: '2026-10-01' }] };
  assert.equal(decodeStore(store)[0].alias, 'docs');
});

test('broken stores produce an error rather than a misleading empty library', () => {
  for (const store of [null, [], { links: {} }, { links: [null] },
    { links: [{ alias: 'docs', url: 'https://swift.org', tags: 'dev' }] },
    { links: [{ alias: 'docs', url: 12 }] }]) {
    assert.throws(() => decodeStore(store));
  }
});
