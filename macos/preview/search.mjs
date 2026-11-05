// Mirrors linkScore() and PanelModel.matches in ../LinkerApp.swift.
export function linkScore(needle, haystack) {
  if (!needle) return 0;
  const n = Array.from(needle.toLowerCase());
  const h = Array.from(haystack.toLowerCase());
  if (n.length > h.length) return null;
  let total = 0;
  let previous = -1;
  for (const character of n) {
    const index = h.indexOf(character, previous + 1);
    if (index === -1) return null;
    let points = 1;
    if (previous >= 0 && index === previous + 1) points++;
    if (index === 0 || '-_/.@ '.includes(h[index - 1])) points += 3;
    total += points;
    previous = index;
  }
  if (n.every((character, index) => h[index] === character)) total += 5;
  if (n.length === h.length) total += 2;
  return total;
}

export function matches(links, query = '', tag = null) {
  const q = query.trim().toLowerCase();
  const candidates = links.filter(link => tag === null || link.tags.includes(tag));
  const alphabetical = (a, b) => a.alias < b.alias ? -1 : a.alias > b.alias ? 1 : 0;
  if (!q) return [...candidates].sort(alphabetical);
  return candidates.flatMap(link => {
    const aliasScore = linkScore(q, link.alias);
    if (aliasScore !== null) return [{ link, score: aliasScore * 3 }];
    const scores = [link.url, link.tags.join(','), link.note]
      .filter(Boolean).map(blob => linkScore(q, blob)).filter(score => score !== null);
    return scores.length ? [{ link, score: Math.max(...scores) }] : [];
  }).sort((a, b) => b.score - a.score || alphabetical(a.link, b.link)).map(item => item.link);
}

export function decodeStore(store) {
  if (!store || Array.isArray(store) || typeof store !== 'object' ||
      (store.version != null && !Number.isInteger(store.version)) ||
      (store.links != null && !Array.isArray(store.links))) throw new Error('Invalid store');
  return (store.links ?? []).flatMap(link => {
    if (!link || typeof link.alias !== 'string' || typeof link.url !== 'string' ||
        (link.tags != null && (!Array.isArray(link.tags) || link.tags.some(tag => typeof tag !== 'string'))) ||
        (link.note != null && typeof link.note !== 'string') ||
        (link.copy_count != null && !Number.isInteger(link.copy_count)) ||
        (link.last_copied != null && typeof link.last_copied !== 'string')) throw new Error('Invalid link');
    if (!link.alias || !link.url) return [];
    return [{ alias: link.alias, url: link.url, tags: [...new Set(link.tags ?? [])].sort(), note: link.note ?? '' }];
  });
}
