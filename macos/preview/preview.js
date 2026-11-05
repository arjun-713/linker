import { decodeStore, matches } from './search.mjs';

const $ = selector => document.querySelector(selector);
const panel = $('#linker-panel');
const search = $('#search');
const list = $('#link-results');
const region = $('#results-region');
const params = new URLSearchParams(location.search);
let sampleLinks = [];
let loadedLinks = [];
let links = [];
let currentMatches = [];
let selected = 0;
let selectedTag = null;
let copiedAlias = null;
let loadError = false;
let copyPending = false;
let actionError = '';
let dismissal;
let generation = 0;
let sourceName = 'Sample library';

function svg(name, className = 'icon') {
  const node = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  node.setAttribute('class', className);
  node.setAttribute('aria-hidden', 'true');
  const use = document.createElementNS(node.namespaceURI, 'use');
  use.setAttribute('href', `#i-${name}`);
  node.append(use);
  return node;
}

function textElement(tag, text, className) {
  const node = document.createElement(tag);
  node.textContent = text;
  if (className) node.className = className;
  return node;
}

function setTheme(theme) {
  document.documentElement.dataset.theme = theme === 'light' ? 'light' : 'dark';
  for (const button of document.querySelectorAll('[data-theme-choice]')) {
    button.setAttribute('aria-pressed', String(button.dataset.themeChoice === document.documentElement.dataset.theme));
  }
}

function renderTags() {
  const tags = [...new Set(links.flatMap(link => link.tags))].sort();
  const fragment = document.createDocumentFragment();
  for (const tag of [null, ...tags]) {
    const button = textElement('button', tag ?? 'All links');
    button.type = 'button';
    button.setAttribute('aria-pressed', String(tag === selectedTag));
    button.setAttribute('aria-label', tag === null ? 'Show all links' : `Filter by ${tag}`);
    button.addEventListener('click', () => {
      selectedTag = tag;
      selected = 0;
      for (const other of $('#tag-filters').children) {
        other.setAttribute('aria-pressed', String(other === button));
      }
      renderResults();
    });
    fragment.append(button);
  }
  $('#tag-filters').replaceChildren(fragment);
}

function updateSelection(scroll = false) {
  selected = Math.max(0, Math.min(selected, currentMatches.length - 1));
  for (let index = 0; index < list.children.length; index++) {
    list.children[index].setAttribute('aria-selected', String(index === selected));
  }
  const row = list.children[selected];
  if (row) {
    search.setAttribute('aria-activedescendant', row.id);
    if (scroll) {
      const bounds = row.getBoundingClientRect();
      const viewport = region.getBoundingClientRect();
      if (bounds.bottom > viewport.bottom) region.scrollTop += bounds.bottom - viewport.bottom + 4;
      if (bounds.top < viewport.top) region.scrollTop -= viewport.top - bounds.top + 4;
    }
  } else {
    search.removeAttribute('aria-activedescendant');
  }
  $('#copy-selected').disabled = !row;
  $('#open-selected').disabled = !row;
}

function renderMessage(kind) {
  const message = $('#message');
  message.replaceChildren();
  let title, detail, symbol;
  if (kind === 'error') {
    title = 'Couldn’t load your links';
    detail = 'Linker couldn’t read links.json. Check the file, then try again.';
    symbol = 'warning';
  } else if (kind === 'empty') {
    title = 'Your links start here';
    detail = 'Save a link in Terminal. It’ll be here when you need it.';
    symbol = 'add-link';
  } else {
    title = 'No links found';
    detail = 'Try another alias, URL, tag or note.';
    symbol = 'search';
  }
  message.append(svg(symbol), textElement('h2', title), textElement('p', detail));
  if (kind === 'empty') {
    message.append(textElement('code', 'linker add github https://github.com'));
  } else {
    const button = textElement('button', kind === 'error' ? 'Try again' : 'Clear filters');
    button.type = 'button';
    button.addEventListener('click', () => {
      if (kind === 'error' && sourceName !== 'Sample library') {
        $('#file-input').click();
      } else if (kind === 'error') {
        $('#preview-state').value = 'library';
        applyState('library');
      } else {
        selectedTag = null;
        search.value = '';
        selected = 0;
        renderTags();
        renderResults();
        search.focus({ preventScroll: true });
      }
    });
    message.append(button);
  }
}

function renderResults({ resetScroll = true } = {}) {
  const previousScroll = region.scrollTop;
  currentMatches = matches(links, search.value, selectedTag);
  $('#list-title').textContent = search.value ? 'Search results' : selectedTag ?? 'Your links';
  $('#result-count').textContent = `${currentMatches.length} ${currentMatches.length === 1 ? 'link' : 'links'}`;
  $('#clear-search').hidden = !search.value;
  const empty = !currentMatches.length;
  $('#message').hidden = !empty;
  list.hidden = empty;
  search.setAttribute('aria-expanded', String(!empty));
  if (empty) {
    list.replaceChildren();
    renderMessage(loadError ? 'error' : links.length ? 'no-matches' : 'empty');
  } else {
    const fragment = document.createDocumentFragment();
    currentMatches.forEach((link, index) => {
      const row = document.createElement('button');
      row.type = 'button';
      row.className = `link-row${copiedAlias === link.alias ? ' copied' : ''}`;
      row.id = `link-row-${index}`;
      row.role = 'option';
      row.tabIndex = -1;
      row.setAttribute('aria-label', `Copy ${link.alias}, ${link.url}`);
      row.title = [link.url, ...link.tags, link.note].filter(Boolean).join(' · ');
      row.append(svg('link', 'icon row-icon'));
      const info = document.createElement('span');
      info.className = 'link-info';
      info.append(textElement('span', link.alias, 'link-alias'));
      info.append(textElement('span', link.url.replace(/^https?:\/\//, ''), 'link-url'));
      row.append(info);
      if (link.tags[0]) row.append(textElement('span', link.tags[0], 'tag'));
      row.append(svg(copiedAlias === link.alias ? 'check' : 'return', 'icon row-action'));
      row.addEventListener('pointermove', () => {
        if (selected !== index) { selected = index; updateSelection(); }
      });
      row.addEventListener('click', () => { selected = index; updateSelection(); copySelected(); });
      fragment.append(row);
    });
    list.replaceChildren(fragment);
  }
  region.scrollTop = resetScroll ? 0 : previousScroll;
  updateSelection();
  renderFeedback();
}

function renderFeedback() {
  const feedback = $('#feedback');
  feedback.replaceChildren();
  feedback.hidden = !copiedAlias && !actionError;
  $('#footer-actions').hidden = !feedback.hidden;
  if (copiedAlias) feedback.append(svg('check-circle'), textElement('span', `Copied ${copiedAlias} to clipboard`));
  else if (actionError) feedback.append(textElement('span', actionError));
}

async function copySelected() {
  const link = currentMatches[selected];
  if (!link || copiedAlias || copyPending) return;
  const token = generation;
  copyPending = true;
  actionError = '';
  try {
    await navigator.clipboard.writeText(link.url);
    if (token !== generation) return;
    copiedAlias = link.alias;
    renderResults({ resetScroll: false });
    dismissal = setTimeout(() => hidePanel('URL copied. Ready for the next one.'), 850);
  } catch {
    if (token !== generation) return;
    actionError = 'Couldn’t copy. Press Return to try again.';
    renderFeedback();
    search.focus({ preventScroll: true });
  } finally {
    if (token === generation) copyPending = false;
  }
}

function openSelected() {
  const link = currentMatches[selected];
  if (!link) return;
  try {
    const url = new URL(link.url);
    // Imported stores are local data, never executable page content.
    if (!['http:', 'https:', 'mailto:'].includes(url.protocol)) throw new Error('Unsupported URL');
    const opened = window.open(url.href, '_blank');
    if (!opened) throw new Error('Popup blocked');
    opened.opener = null;
    hidePanel('Link opened. Your library is right here.');
  } catch {
    actionError = 'Couldn’t open this URL. You can still copy it.';
    renderFeedback();
  }
}

function hidePanel(message = 'Your links are a keystroke away.') {
  generation++;
  clearTimeout(dismissal);
  copyPending = false;
  panel.hidden = true;
  $('#closed-panel').hidden = false;
  $('#closed-message').textContent = message;
  $('#menu-toggle').setAttribute('aria-expanded', 'false');
  $('#menu-toggle').focus({ preventScroll: true });
}

function showPanel() {
  generation++;
  clearTimeout(dismissal);
  copyPending = false;
  copiedAlias = null;
  actionError = '';
  search.value = '';
  selectedTag = null;
  selected = 0;
  panel.hidden = false;
  $('#closed-panel').hidden = true;
  $('#menu-toggle').setAttribute('aria-expanded', 'true');
  renderTags();
  renderResults();
  search.focus({ preventScroll: true });
}

function applyState(state) {
  loadError = state === 'error';
  links = state === 'empty' || loadError ? [] : loadedLinks;
  showPanel();
  if (state === 'no-matches') {
    search.value = 'zzzzzz';
    renderResults();
  }
}

function reset() {
  loadedLinks = sampleLinks;
  sourceName = 'Sample library';
  $('#source-label').textContent = sourceName;
  $('#import-status').textContent = '';
  $('#preview-state').value = 'library';
  applyState('library');
}

search.addEventListener('input', () => { selected = 0; renderResults(); });
$('#clear-search').addEventListener('click', () => {
  search.value = ''; selected = 0; renderResults(); search.focus({ preventScroll: true });
});
$('#copy-selected').addEventListener('click', copySelected);
$('#open-selected').addEventListener('click', openSelected);
$('#menu-toggle').addEventListener('click', () => panel.hidden ? showPanel() : hidePanel());
$('#reopen').addEventListener('click', showPanel);
$('#reload').addEventListener('click', () => {
  // The preview reloads its in-memory file. Native Linker rereads the store on disk.
  const state = $('#preview-state').value;
  if (state === 'error' && sourceName !== 'Sample library') return $('#file-input').click();
  if (state === 'error') return reset();
  actionError = '';
  copiedAlias = null;
  copyPending = false;
  generation++;
  clearTimeout(dismissal);
  selected = 0;
  renderResults();
});
$('#preview-state').addEventListener('change', event => applyState(event.target.value));
$('#reset-preview').addEventListener('click', reset);
for (const button of document.querySelectorAll('[data-theme-choice]')) {
  button.addEventListener('click', () => setTheme(button.dataset.themeChoice));
}
$('#load-file').addEventListener('click', () => $('#file-input').click());
$('#file-input').addEventListener('change', async event => {
  const file = event.target.files[0];
  if (!file) return;
  sourceName = file.name;
  $('#source-label').textContent = sourceName;
  try {
    loadedLinks = decodeStore(JSON.parse(await file.text()));
    $('#import-status').textContent = `Loaded ${loadedLinks.length} links locally. The file stays in your browser.`;
    $('#preview-state').value = 'library';
    applyState('library');
  } catch {
    $('#import-status').textContent = 'Choose a valid Linker JSON export to try again.';
    $('#preview-state').value = 'error';
    applyState('error');
  }
  event.target.value = '';
});
$('#stage').addEventListener('pointerdown', event => {
  if (event.target === $('#stage') && !panel.hidden) hidePanel();
});
document.addEventListener('keydown', event => {
  const command = event.metaKey || event.ctrlKey;
  if (command && event.shiftKey && event.key.toLowerCase() === 'l') {
    event.preventDefault();
    panel.hidden ? showPanel() : hidePanel();
    return;
  }
  if (panel.hidden || !panel.contains(document.activeElement)) return;
  if (event.key === 'Escape') { event.preventDefault(); hidePanel(); }
  else if (command && event.key.toLowerCase() === 'f') {
    event.preventDefault(); search.focus({ preventScroll: true });
  } else if (command && event.key.toLowerCase() === 'r') {
    event.preventDefault(); $('#reload').click();
  } else if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
    event.preventDefault();
    selected += event.key === 'ArrowDown' ? 1 : -1;
    updateSelection(true);
  } else if (event.key === 'Enter') {
    // Native buttons retain their usual keyboard activation.
    if (!command && document.activeElement !== search) return;
    event.preventDefault(); command ? openSelected() : copySelected();
  }
});

setTheme(params.get('theme'));
try {
  const response = await fetch('sample-links.json');
  if (!response.ok) throw new Error('Sample file unavailable');
  sampleLinks = decodeStore(await response.json());
  loadedLinks = sampleLinks;
  const state = ['library', 'no-matches', 'empty', 'error'].includes(params.get('state')) ? params.get('state') : 'library';
  $('#preview-state').value = state;
  applyState(state);
} catch {
  sourceName = 'Sample library';
  $('#preview-state').value = 'error';
  applyState('error');
  $('#import-status').textContent = 'Start with python3 macos/preview.py, then open the localhost URL.';
}
