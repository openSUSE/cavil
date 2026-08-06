// Rank known license names for an autocomplete field. Every space-separated word in the query must appear
// somewhere in the name (case-insensitive), then survivors are ordered by how closely they match: exact
// hit, prefix hit, earliest position of the query, shorter name, finally alphabetical for stability. An
// empty query returns the suggestions unchanged. Shared by the snippet and pattern editors.
export function rankLicenses(suggestions, query) {
  if (query === '') return suggestions;

  const words = query.split(' ').filter(w => w.length > 0);
  let results = suggestions;
  for (const word of words) {
    results = results.filter(name => name.toLowerCase().includes(word.toLowerCase()));
  }

  const q = query.toLowerCase();
  return [...results].sort((a, b) => {
    const al = a.toLowerCase();
    const bl = b.toLowerCase();
    // 1. Exact match wins
    const aExact = al === q;
    const bExact = bl === q;
    if (aExact !== bExact) return aExact ? -1 : 1;
    // 2. Prefix match beats substring match
    const aStarts = al.startsWith(q);
    const bStarts = bl.startsWith(q);
    if (aStarts !== bStarts) return aStarts ? -1 : 1;
    // 3. Earlier position of the query beats later
    const aIdx = al.indexOf(q);
    const bIdx = bl.indexOf(q);
    if (aIdx !== bIdx) return aIdx - bIdx;
    // 4. Shorter names beat longer ones (less surrounding noise)
    if (a.length !== b.length) return a.length - b.length;
    // 5. Stable alphabetical fallback
    return a.localeCompare(b);
  });
}
