import {Decoration, MatchDecorator, ViewPlugin} from '@codemirror/view';

// Comment templates mark the bits a reviewer has to fill in with [UPPER_CASE] tokens. The syntax is
// deliberately narrow (an uppercase letter followed by uppercase letters, digits and underscores) so
// ordinary prose like [see above] or a footnote marker like [1] is never mistaken for one.
const PLACEHOLDER_SOURCE = '\\[[A-Z][A-Z0-9_]*\\]';

// Always a fresh RegExp: a shared global regexp carries a mutable lastIndex between call sites
function placeholderRegExp() {
  return new RegExp(PLACEHOLDER_SOURCE, 'g');
}

export function findPlaceholders(text) {
  const found = [];
  for (const match of text.matchAll(placeholderRegExp())) {
    found.push({from: match.index, to: match.index + match[0].length, name: match[0]});
  }
  return found;
}

export function placeholderAt(text, pos) {
  // A position right after the closing bracket is not inside the placeholder, so a click there gives an
  // ordinary caret and two adjacent placeholders cannot both claim the boundary
  return findPlaceholders(text).find(p => pos >= p.from && pos < p.to) ?? null;
}

export function nextPlaceholder(text, pos) {
  return findPlaceholders(text).find(p => p.from > pos) ?? null;
}

export function previousPlaceholder(text, pos) {
  return findPlaceholders(text).findLast(p => p.to <= pos) ?? null;
}

// Highlighting is a pure function of the text, which is what MatchDecorator is for. Note that it only
// decorates the visible viewport, so anything that needs all placeholders (click handling, tab jumps,
// the pre-submit check) has to scan the document text instead of the decoration set.
export function placeholderHighlighter() {
  const matcher = new MatchDecorator({
    regexp: placeholderRegExp(),
    decoration: Decoration.mark({class: 'cavil-placeholder'})
  });
  return ViewPlugin.fromClass(
    class {
      constructor(view) {
        this.placeholders = matcher.createDeco(view);
      }
      update(update) {
        this.placeholders = matcher.updateDeco(update, this.placeholders);
      }
    },
    {decorations: plugin => plugin.placeholders}
  );
}
