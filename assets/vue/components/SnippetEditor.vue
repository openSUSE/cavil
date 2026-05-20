<template>
  <div class="row mt-3 snippet-editor">
    <h3 v-if="mode === 'page'">Edit Snippet</h3>
    <div v-if="patternText === null"><i class="fa-solid fa-rotate fa-spin"></i> Loading snippet...</div>
    <div v-else>
      <div v-if="hasContributorRole === false && hasAdminRole === false" class="alert alert-info">
        There is no license pattern for this snippet yet. You do not have the necessary permissions to propose new
        license patterns. To change this contact an administrator and request the "contributor" role.
      </div>
      <div v-else-if="hasAdminRole === false" class="alert alert-info">
        There is no license pattern for this snippet yet, you are welcome to submit a proposal. An administrator will
        review it and decide if it should be added. However, you may only use existing licenses and risk assessments.
      </div>
      <div v-if="this.package !== null" class="row">
        <div class="col mb-3">
          The example shown here is from the file <a :href="this.package.fileUrl">{{ this.package.file }}</a> in the
          package <a :href="this.package.packageUrl">{{ this.package.name }}</a
          >.
        </div>
      </div>
      <div class="snippet-editor-form">
        <div class="row">
          <div class="col mb-3">
            <label class="form-label" for="pattern">Snippet</label>
            <div ref="editorHost" class="snippet-editor-host"></div>
            <textarea
              ref="patternText"
              v-model="patternText"
              class="mono-text form-control snippet-editor-textarea"
              id="pattern"
              name="pattern"
              rows="20"
            ></textarea>
            <div id="patternHelp" class="snippet-editor-hints">
              <div class="snippet-editor-hints-header">
                <i class="fa-solid fa-circle-info"></i>
                Editing tips
              </div>
              <dl class="snippet-editor-hints-list">
                <dt><span class="snippet-editor-hints-swatch keyword-line"></span></dt>
                <dd>Keyword match &mdash; include in the license pattern</dd>
                <dt><span class="snippet-editor-hints-swatch license-line"></span></dt>
                <dd>Existing pattern match &mdash; safe to remove</dd>
                <dt><code>$SKIP5</code></dt>
                <dd>Skip up to 5 words at this position</dd>
                <dt><code>$SKIP19</code></dt>
                <dd>Skip as many words as the matching engine allows</dd>
                <template v-if="hasAdminRole === true">
                  <dt>Hover / gutter</dt>
                  <dd>Hover a highlighted line for pattern details, or click the line number to open it</dd>
                </template>
              </dl>
            </div>
          </div>
        </div>
        <div class="row">
          <div class="col mb-3">
            <label class="form-label" for="license">License</label>
            <input
              v-model="license"
              @input="autocomplete"
              @keydown="licenseFocused = true"
              @focus="licenseFocused = true"
              @blur="licenseFocused = false"
              ref="license"
              type="text"
              class="form-control"
              id="license"
              name="license"
              autocomplete="off"
            />
            <div v-show="licenseFocused" class="autocomplete-container">
              <div class="autocomplete">
                <div
                  v-for="(result, i) in results"
                  :key="i"
                  @mousedown.prevent="fillLicense(result)"
                  class="autocomplete-item"
                >
                  {{ result }}
                </div>
              </div>
            </div>
            <div id="patternHelp" class="form-text">
              Auto-completed license names will also predict the risk value.
              <a
                data-bs-html="true"
                data-bs-toggle="popover"
                data-bs-trigger="hover focus"
                data-bs-title="Standard Risks"
                :data-bs-content="riskHtml"
              >
                <i class="fa-solid fa-circle-question"></i>
              </a>
            </div>
          </div>
        </div>
        <div class="row">
          <div class="col mb-3">
            <div class="snippet-editor-attributes">
              <div class="snippet-editor-attributes-header">Attributes</div>
              <div class="snippet-editor-attributes-body">
                <div class="snippet-editor-attribute snippet-editor-attribute-risk">
                  <label for="risk" class="form-label">Risk</label>
                  <select v-model="licenseOptions.risk" name="risk" id="risk" class="form-control form-select">
                    <option>0</option>
                    <option>1</option>
                    <option>2</option>
                    <option>3</option>
                    <option>4</option>
                    <option>5</option>
                    <option>6</option>
                    <option>9</option>
                  </select>
                </div>
                <div class="snippet-editor-attribute snippet-editor-attribute-flags">
                  <label class="form-label">Flags</label>
                  <div class="snippet-editor-attribute-flag-list">
                    <div class="form-check">
                      <input
                        v-model="licenseOptions.patent"
                        type="checkbox"
                        class="form-check-input"
                        id="patent"
                        name="patent"
                        value="1"
                      />
                      <label class="form-check-label" for="patent">Patent</label>
                    </div>
                    <div class="form-check">
                      <input
                        v-model="licenseOptions.trademark"
                        type="checkbox"
                        class="form-check-input"
                        id="trademark"
                        name="trademark"
                        value="1"
                      />
                      <label class="form-check-label" for="trademark">Trademark</label>
                    </div>
                    <div class="form-check">
                      <input
                        v-model="licenseOptions.export_restricted"
                        type="checkbox"
                        class="form-check-input"
                        id="export_restricted"
                        name="export_restricted"
                        value="1"
                      />
                      <label class="form-check-label" for="export_restricted">Export Restricted</label>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
        <div class="row">
          <div class="col mb-3 snippet-editor-actions">
            <div class="snippet-editor-action-buttons">
              <div v-if="hasAdminRole === true" class="btn-group">
                <button
                  type="button"
                  class="btn btn-success"
                  data-action="create-pattern"
                  @click="emitAction('create-pattern')"
                >
                  {{ actionLabel('create-pattern') }}
                </button>
                <template v-if="hash !== null && from !== null && edited === '0'">
                  <button
                    type="button"
                    class="btn btn-success dropdown-toggle dropdown-toggle-split"
                    data-bs-toggle="dropdown"
                    aria-expanded="false"
                    aria-label="More admin actions"
                  ></button>
                  <ul class="dropdown-menu">
                    <li>
                      <a
                        class="dropdown-item"
                        href="#"
                        data-action="create-ignore"
                        @click.prevent="emitAction('create-ignore')"
                      >
                        {{ actionLabel('create-ignore') }}
                      </a>
                    </li>
                    <li>
                      <a
                        class="dropdown-item"
                        href="#"
                        data-action="mark-non-license"
                        @click.prevent="emitAction('mark-non-license')"
                      >
                        {{ actionLabel('mark-non-license') }}
                      </a>
                    </li>
                  </ul>
                </template>
              </div>
              <div v-if="hasContributorRole === true" class="btn-group">
                <button
                  type="button"
                  class="btn btn-success"
                  data-action="propose-pattern"
                  @click="emitAction('propose-pattern')"
                >
                  {{ actionLabel('propose-pattern') }}
                </button>
                <template v-if="hash !== null && from !== null && edited === '0'">
                  <button
                    type="button"
                    class="btn btn-success dropdown-toggle dropdown-toggle-split"
                    data-bs-toggle="dropdown"
                    aria-expanded="false"
                    aria-label="More proposal actions"
                  ></button>
                  <ul class="dropdown-menu">
                    <li>
                      <a
                        class="dropdown-item"
                        href="#"
                        data-action="propose-ignore"
                        @click.prevent="emitAction('propose-ignore')"
                      >
                        {{ actionLabel('propose-ignore') }}
                      </a>
                    </li>
                    <li>
                      <a
                        class="dropdown-item"
                        href="#"
                        data-action="propose-missing"
                        @click.prevent="emitAction('propose-missing')"
                      >
                        {{ actionLabel('propose-missing') }}
                      </a>
                    </li>
                  </ul>
                </template>
              </div>
            </div>
          </div>
        </div>
        <div v-if="closest !== null" class="row closest-container">
          <div class="col">
            <div class="closest-header">
              <a :href="closest.url">
                <b>{{ closest.similarity }}%</b> similarity to
                <b>{{ closest.license === '' ? 'Keyword Pattern' : closest.license }}</b
                >, estimated risk {{ closest.license === '' ? 9 : closest.risk }}
              </a>
            </div>
            <div class="closest-source">
              <pre>{{ closest.text }}</pre>
            </div>
            <div class="closest-footer">
              <span v-if="closest.package !== ''"><b>Package:</b> {{ closest.package }}</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script>
import {setupPopoverDelayed} from '../helpers/links.js';
import {EditorState, StateField} from '@codemirror/state';
import {Decoration, EditorView, hoverTooltip, lineNumbers} from '@codemirror/view';
import UserAgent from '@mojojs/user-agent';

export default {
  name: 'SnippetEditor',
  props: {
    snippetId: {type: Number, required: true},
    hash: {type: String, default: null},
    from: {type: String, default: null},
    hasContributorRole: {type: Boolean, default: false},
    hasAdminRole: {type: Boolean, default: false},
    mode: {type: String, default: 'page'},
    initial: {type: Object, default: null}
  },
  emits: ['submit'],
  data() {
    return {
      closest: null,
      closestUrl: '/snippet/closest',
      decorationsField: null,
      edited: '0',
      editor: null,
      editorReady: this.mode !== 'batch',
      highlightedKeywords: '',
      highlightedLicenses: '',
      keywords: {},
      license: '',
      licenseFocused: false,
      licenses: {},
      licenseOptions: {
        export_restricted: false,
        patent: false,
        risk: 1,
        trademark: false
      },
      matches: {},
      package: null,
      patternMeta: new Map(),
      patternMetaPromises: new Map(),
      patternText: null,
      results: [],
      riskHtml:
        '<b>Low risk licenses</b><br>' +
        '<b>1:</b> Public-Domain<br>' +
        '<b>2:</b> BSD-2-Clause, MIT<br>' +
        '<b>3:</b> LGPL-2.0-only, LGPL-2.1-or-later<br>' +
        '<b>4:</b> GPL-2.0-only, GPL-3.0-or-later<br>' +
        '<b>Medium risk licenses</b><br>' +
        '<b>5:</b> AGPL-3.0-or-later<br>' +
        '<b>High risk licenses</b><br>' +
        '<b>6:</b> SSPL-1.0<br>' +
        '<b>7:</b> Non-Commercial<br>' +
        '<b>Unknown risk (reserved)</b><br>' +
        '<b>9:</b> Keyword patterns',
      snippetUrl: `/snippet/meta/${this.snippetId}`,
      startLine: null,
      suggestions: [],
      ua: new UserAgent({baseURL: window.location.href})
    };
  },
  async mounted() {
    await this.getSnippet();
    await this.$nextTick();
    setupPopoverDelayed();
    this.maybeSetupCodeMirror();
    await this.getClosest();
  },
  beforeUnmount() {
    if (this.editor) {
      this.editor.destroy();
      this.editor = null;
    }
  },
  methods: {
    actionLabel(action) {
      const labels = {
        'create-pattern': 'Create Pattern',
        'create-ignore': 'Ignore Pattern',
        'mark-non-license': 'No Legal Text',
        'propose-pattern': 'Propose Pattern',
        'propose-ignore': 'Propose Ignore',
        'propose-missing': 'Missing License'
      };
      return labels[action];
    },
    autocomplete() {
      const license = this.license;
      if (license === '') {
        this.results = this.suggestions;
        return;
      }
      const words = license.split(' ').filter(w => w.length > 0);
      let results = this.suggestions;
      for (const word of words) {
        results = results.filter(name => name.toLowerCase().includes(word.toLowerCase()));
      }
      const q = license.toLowerCase();
      results = [...results].sort((a, b) => {
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
      this.results = results;
    },
    fillLicense(result) {
      if (this.$refs.license) this.$refs.license.blur();
      this.license = result;
      if (this.licenses[result] !== undefined) this.licenseOptions = this.licenses[result];
      this.results = this.suggestions;
      this.licenseFocused = false;
    },
    async getClosest() {
      const text = this.editor ? this.editor.state.doc.toString() : this.patternText;
      if (text == null) return;
      const res = await this.ua.post(this.closestUrl, {form: {text}});
      const data = await res.json();
      this.closest = data.pattern;
      if (this.closest !== null) this.closest.url = `/licenses/edit_pattern/${this.closest.id}`;
    },
    async getSnippet() {
      const res = await this.ua.get(this.snippetUrl);
      const data = await res.json();

      const snippet = data.snippet;
      this.package = snippet.package;
      if (this.package !== null) {
        this.package.packageUrl = `/reviews/details/${this.package.id}`;
        this.package.fileUrl = `/reviews/file_view/${this.package.id}/${this.package.filename}`;
        this.package.file = this.package.filename.split('/').pop();
      }
      this.patternText = snippet.text;
      this.startLine = snippet.sline;
      this.matches = snippet.matches;
      this.keywords = snippet.keywords;
      this.licenses = data.licenses;
      this.suggestions = Object.keys(this.licenses);
      this.results = this.suggestions;

      // The form (and refs like patternText/license) is gated by v-if on
      // patternText; wait one tick so the DOM is in place before we touch refs.
      await this.$nextTick();

      if (data.closest !== null) this.fillLicense(data.closest);
      if (this.initial !== null) this.applyInitial(this.initial);
    },
    applyInitial(initial) {
      if (initial.pattern !== undefined) this.patternText = initial.pattern;
      if (initial.license !== undefined) this.license = initial.license;
      if (initial.risk !== undefined) this.licenseOptions.risk = Number(initial.risk);
      this.licenseOptions.patent = initial.patent === '1' || initial.patent === true;
      this.licenseOptions.trademark = initial.trademark === '1' || initial.trademark === true;
      this.licenseOptions.export_restricted = initial.export_restricted === '1' || initial.export_restricted === true;
      if (initial.edited !== undefined) this.edited = String(initial.edited);
      if (initial['highlighted-keywords'] !== undefined) {
        this.highlightedKeywords = initial['highlighted-keywords'];
      }
      if (initial['highlighted-licenses'] !== undefined) {
        this.highlightedLicenses = initial['highlighted-licenses'];
      }
    },
    getHighlightedLines() {
      if (!this.editor || !this.decorationsField) return;
      const matchLines = [];
      const keywordLines = [];
      const state = this.editor.state;
      const set = state.field(this.decorationsField);
      set.between(0, state.doc.length, (from, _to, deco) => {
        const cls = deco.spec.attributes?.class ?? '';
        const lineNo = state.doc.lineAt(from).number - 1;
        if (cls.includes('license-line')) matchLines.push(lineNo);
        if (cls.includes('keyword-line')) keywordLines.push(lineNo);
      });
      this.highlightedKeywords = keywordLines.join(',');
      this.highlightedLicenses = matchLines.join(',');
    },
    refreshEditor() {
      // Modal host signals the modal is fully shown. In batch mode this is our
      // cue that the host has its real dimensions, so it is now safe to
      // attach CodeMirror (or remeasure it if it was already attached).
      this.editorReady = true;
      if (this.editor) {
        this.editor.requestMeasure();
        return;
      }
      this.maybeSetupCodeMirror();
    },
    maybeSetupCodeMirror() {
      if (!this.editorReady) return;
      this.setupCodeMirror();
    },
    setupCodeMirror() {
      if (this.editor || !this.$refs.patternText || !this.$refs.editorHost) return;

      const matchLineSet = {};
      const keywordLineSet = {};
      const idsByLine = new Map();
      const collect = (map, into) => {
        for (const [line, pid] of Object.entries(map)) {
          const i = parseInt(line);
          into[i] = true;
          const list = idsByLine.get(i) ?? [];
          if (!list.includes(String(pid))) list.push(String(pid));
          idsByLine.set(i, list);
        }
      };
      collect(this.matches, matchLineSet);
      collect(this.keywords, keywordLineSet);

      const startLine = this.startLine ?? 1;
      const decoField = StateField.define({
        create: state => {
          const ranges = [];
          const sorted = [...idsByLine.keys()].sort((a, b) => a - b);
          for (const lineIdx of sorted) {
            const cmLineNo = lineIdx + 1;
            if (cmLineNo < 1 || cmLineNo > state.doc.lines) continue;
            const line = state.doc.line(cmLineNo);
            const classes = ['found-pattern'];
            if (matchLineSet[lineIdx]) classes.push('license-line');
            if (keywordLineSet[lineIdx]) classes.push('keyword-line');
            ranges.push(
              Decoration.line({
                attributes: {
                  class: classes.join(' '),
                  'data-pattern-ids': (idsByLine.get(lineIdx) ?? []).join(' ')
                }
              }).range(line.from)
            );
          }
          return Decoration.set(ranges, true);
        },
        update: (decos, tr) => (tr.docChanged ? decos.map(tr.changes) : decos),
        provide: f => EditorView.decorations.from(f)
      });
      this.decorationsField = decoField;

      const baseTheme = EditorView.theme({
        '&': {fontSize: '13px', height: '600px'},
        '.cm-scroller': {fontFamily: 'monospace, monospace', overflow: 'auto'},
        '.cm-gutters': {
          backgroundColor: '#f6f8fa',
          color: '#6e7781',
          borderRight: '1px solid #d0d7de'
        },
        '.cm-lineNumbers .cm-gutterElement': {padding: '0 8px 0 6px'},
        '.cm-lineNumbers .cm-gutterElement.has-pattern': {
          color: '#0969da',
          cursor: 'pointer',
          fontWeight: '600'
        }
      });

      const state = EditorState.create({
        doc: this.patternText ?? '',
        extensions: [
          lineNumbers({
            formatNumber: n => String(n + startLine - 1),
            domEventHandlers: {
              click: (view, line) => this.onGutterClick(view, line)
            }
          }),
          decoField,
          hoverTooltip((view, pos) => this.makeHoverTooltip(view, pos), {hideOnChange: true}),
          EditorView.updateListener.of(update => this.onCmUpdate(update)),
          baseTheme
        ]
      });

      this.editor = new EditorView({parent: this.$refs.editorHost, state});
      // Expose the view on the .cm-editor element so external code (e.g. tests)
      // can reach the EditorView the same way CM5 attached .CodeMirror.
      this.editor.dom.cmView = this.editor;
      this.$refs.patternText.classList.add('snippet-editor-textarea-hidden');
      this.getHighlightedLines();
    },
    onCmUpdate(update) {
      if (update.docChanged) {
        this.edited = '1';
        this.patternText = update.state.doc.toString();
      }
      if (update.focusChanged && !update.view.hasFocus) {
        this.getClosest();
        this.getHighlightedLines();
      }
    },
    onGutterClick(view, line) {
      const ids = this.patternIdsAtPos(view, line.from);
      if (ids.length === 0) return false;
      window.open(`/licenses/edit_pattern/${ids[0]}`, '_blank', 'noopener');
      return true;
    },
    patternIdsAtPos(view, pos) {
      if (!this.decorationsField) return [];
      const lineStart = view.state.doc.lineAt(pos).from;
      let ids = [];
      view.state.field(this.decorationsField).between(lineStart, lineStart, (_from, _to, deco) => {
        const attr = deco.spec.attributes?.['data-pattern-ids'];
        if (attr) ids = attr.split(' ').filter(Boolean);
      });
      return ids;
    },
    makeHoverTooltip(view, pos) {
      const ids = this.patternIdsAtPos(view, pos);
      if (ids.length === 0) return null;
      const lineStart = view.state.doc.lineAt(pos).from;
      return {
        pos: lineStart,
        above: true,
        create: () => {
          const dom = document.createElement('div');
          dom.className = 'cavil-pattern-tip';
          this.renderTooltip(dom, ids);
          return {dom};
        }
      };
    },
    async renderTooltip(dom, ids) {
      dom.innerHTML =
        '<div class="cavil-pattern-tip-loading"><i class="fa-solid fa-spinner fa-pulse"></i> Loading…</div>';
      try {
        const metas = await Promise.all(ids.map(id => this.fetchPatternMeta(id)));
        const valid = metas.filter(m => m);
        if (valid.length === 0) {
          dom.innerHTML = '<div class="cavil-pattern-tip-error">No pattern info available.</div>';
          return;
        }
        dom.innerHTML = '';
        for (const meta of valid) dom.appendChild(this.buildTooltipCard(meta));
      } catch (e) {
        dom.innerHTML = '<div class="cavil-pattern-tip-error">Failed to load pattern info.</div>';
      }
    },
    fetchPatternMeta(id) {
      if (this.patternMeta.has(id)) return Promise.resolve(this.patternMeta.get(id));
      if (this.patternMetaPromises.has(id)) return this.patternMetaPromises.get(id);
      const promise = (async () => {
        const res = await this.ua.get(`/licenses/pattern/${id}.json`);
        if (!res.isSuccess) return null;
        const meta = await res.json();
        this.patternMeta.set(id, meta);
        return meta;
      })();
      this.patternMetaPromises.set(id, promise);
      return promise;
    },
    buildTooltipCard(meta) {
      const card = document.createElement('div');
      card.className = 'cavil-pattern-tip-card';

      const header = document.createElement('div');
      header.className = 'cavil-pattern-tip-header';
      const title = document.createElement('span');
      title.className = 'cavil-pattern-tip-title';
      title.textContent = meta.license && meta.license !== '' ? meta.license : 'Keyword pattern';
      header.appendChild(title);
      const risk = document.createElement('span');
      risk.className = `cavil-pattern-tip-risk risk-${meta.risk ?? 0}`;
      risk.textContent = `risk ${meta.risk ?? '?'}`;
      header.appendChild(risk);
      card.appendChild(header);

      const preview = document.createElement('pre');
      preview.className = 'cavil-pattern-tip-preview';
      const allLines = (meta.pattern ?? '').split('\n');
      const shown = allLines.slice(0, 6).join('\n');
      preview.textContent = shown + (allLines.length > 6 ? '\n…' : '');
      card.appendChild(preview);

      const footer = document.createElement('div');
      footer.className = 'cavil-pattern-tip-footer';
      const link = document.createElement('a');
      link.href = `/licenses/edit_pattern/${meta.id}`;
      link.target = '_blank';
      link.rel = 'noopener';
      link.textContent = 'Open pattern →';
      footer.appendChild(link);
      card.appendChild(footer);

      return card;
    },
    emitAction(action) {
      if (this.editor) {
        this.patternText = this.editor.state.doc.toString();
        this.getHighlightedLines();
      }
      const formData = {
        pattern: this.patternText,
        license: this.license,
        risk: String(this.licenseOptions.risk),
        edited: this.edited,
        'highlighted-keywords': this.highlightedKeywords,
        'highlighted-licenses': this.highlightedLicenses
      };
      if (this.licenseOptions.patent) formData.patent = '1';
      if (this.licenseOptions.trademark) formData.trademark = '1';
      if (this.licenseOptions.export_restricted) formData.export_restricted = '1';
      if (this.hash !== null) formData.hash = this.hash;
      if (this.from !== null) formData.from = this.from;
      if (this.package !== null) formData.package = this.package.id;
      this.$emit('submit', {action, formData, license: this.license, package: this.package});
    }
  }
};
</script>

<style>
.snippet-editor .snippet-editor-host {
  border: 1px solid #d0d7de;
  border-radius: 6px;
  overflow: hidden;
}
.snippet-editor .snippet-editor-host .cm-editor {
  height: 600px;
}
.snippet-editor .snippet-editor-host .cm-editor.cm-focused {
  outline: none;
}
.snippet-editor .snippet-editor-textarea {
  margin-top: 0.5rem;
}
.snippet-editor .snippet-editor-textarea-hidden {
  display: none;
}
.snippet-editor-hints {
  background: #f6f8fa;
  border: 1px solid #d0d7de;
  border-radius: 6px;
  color: #57606a;
  font-size: 12px;
  margin-top: 0.5rem;
  padding: 10px 14px;
}
.snippet-editor-hints-header {
  align-items: center;
  color: #1f2328;
  display: flex;
  font-weight: 600;
  gap: 6px;
  margin-bottom: 6px;
}
.snippet-editor-hints-list {
  align-items: baseline;
  column-gap: 12px;
  display: grid;
  grid-template-columns: max-content 1fr;
  margin: 0;
  row-gap: 4px;
}
.snippet-editor-hints-list dt {
  font-weight: 500;
  text-align: right;
}
.snippet-editor-hints-list dd {
  margin: 0;
}
.snippet-editor-hints-list code {
  background: rgba(175, 184, 193, 0.2);
  border-radius: 4px;
  color: #1f2328;
  font-size: 11px;
  padding: 1px 5px;
}
.snippet-editor-hints-swatch {
  border: 1px solid rgba(27, 31, 36, 0.1);
  border-radius: 3px;
  display: inline-block;
  height: 12px;
  vertical-align: middle;
  width: 22px;
}
.snippet-editor-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
  align-items: center;
  justify-content: space-between;
}
.snippet-editor-action-buttons {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
  align-items: center;
}

/* Primer form chrome */
.snippet-editor .form-label {
  color: #1f2328;
  font-size: 13px;
  font-weight: 600;
  margin-bottom: 4px;
}
.snippet-editor .form-control,
.snippet-editor .form-select {
  background-color: #ffffff;
  border: 1px solid #d0d7de;
  border-radius: 6px;
  box-shadow: inset 0 1px 0 rgba(208, 215, 222, 0.2);
  color: #1f2328;
  font-size: 14px;
  line-height: 20px;
  padding: 5px 12px;
  transition:
    border-color 0.15s,
    box-shadow 0.15s;
}
.snippet-editor .form-control:focus,
.snippet-editor .form-select:focus {
  background-color: #ffffff;
  border-color: #0969da;
  box-shadow: 0 0 0 3px rgba(9, 105, 218, 0.3);
  color: #1f2328;
  outline: none;
}
.snippet-editor .form-check-input {
  background-color: #ffffff;
  border: 1px solid #6e7781;
  border-radius: 3px;
  box-shadow: none;
  height: 16px;
  margin-top: 0.2rem;
  width: 16px;
}
.snippet-editor .form-check-input:checked {
  background-color: #0969da;
  border-color: #0969da;
}
.snippet-editor .form-check-input:focus {
  border-color: #0969da;
  box-shadow: 0 0 0 3px rgba(9, 105, 218, 0.3);
  outline: none;
}
.snippet-editor .form-check-label {
  color: #1f2328;
  font-size: 14px;
  padding-left: 2px;
  user-select: none;
}

/* Attributes card */
.snippet-editor .snippet-editor-attributes {
  background: #ffffff;
  border: 1px solid #d0d7de;
  border-radius: 6px;
  overflow: hidden;
}
.snippet-editor .snippet-editor-attributes-header {
  background: #f6f8fa;
  border-bottom: 1px solid #d0d7de;
  color: #1f2328;
  font-size: 12px;
  font-weight: 600;
  letter-spacing: 0.02em;
  padding: 6px 12px;
  text-transform: uppercase;
}
.snippet-editor .snippet-editor-attributes-body {
  align-items: flex-start;
  display: flex;
  flex-wrap: wrap;
  gap: 24px;
  padding: 12px 14px 14px;
}
.snippet-editor .snippet-editor-attribute-risk {
  width: 140px;
}
.snippet-editor .snippet-editor-attribute-flag-list {
  align-items: center;
  display: flex;
  flex-wrap: wrap;
  gap: 14px 20px;
  min-height: 32px;
}
.snippet-editor .snippet-editor-attribute-flag-list .form-check {
  margin: 0;
  min-height: 0;
  padding-left: 22px;
}
.snippet-editor .snippet-editor-attribute-flag-list .form-check-input {
  margin-left: -22px;
}

/* Primer-style green buttons */
.snippet-editor .btn-success {
  background-color: #1f883d;
  border: 1px solid rgba(31, 35, 40, 0.15);
  box-shadow: 0 1px 0 rgba(31, 35, 40, 0.04);
  color: #ffffff;
  font-size: 14px;
  font-weight: 500;
  line-height: 20px;
  padding: 5px 16px;
  transition:
    background-color 0.15s,
    box-shadow 0.15s;
}
.snippet-editor .btn-success:hover {
  background-color: #1a7f37;
  border-color: rgba(31, 35, 40, 0.15);
  color: #ffffff;
}
.snippet-editor .btn-success:focus,
.snippet-editor .btn-success.focus {
  background-color: #1a7f37;
  border-color: rgba(31, 35, 40, 0.15);
  box-shadow: 0 0 0 3px rgba(31, 136, 61, 0.4);
  color: #ffffff;
}
.snippet-editor .btn-success:active,
.snippet-editor .btn-success.active {
  background-color: #187432;
  border-color: rgba(31, 35, 40, 0.15);
  box-shadow: inset 0 1px 0 rgba(0, 45, 17, 0.2);
  color: #ffffff;
}
.snippet-editor .btn-success.dropdown-toggle-split {
  padding-left: 8px;
  padding-right: 8px;
}
.snippet-editor .dropdown-menu {
  background: #ffffff;
  border: 1px solid #d0d7de;
  border-radius: 6px;
  box-shadow: 0 8px 24px rgba(140, 149, 159, 0.2);
  font-size: 14px;
  padding: 4px 0;
}
.snippet-editor .dropdown-item {
  color: #1f2328;
  padding: 6px 14px;
}
.snippet-editor .dropdown-item:hover,
.snippet-editor .dropdown-item:focus {
  background-color: #f6f8fa;
  color: #1f2328;
}

/* Primer-style autocomplete popover */
.snippet-editor .autocomplete-container {
  background: #ffffff;
  border: 1px solid #d0d7de;
  border-radius: 6px;
  box-shadow: 0 8px 24px rgba(140, 149, 159, 0.2);
  cursor: pointer;
  margin: 4px 0 0;
  padding: 4px 0;
  z-index: 1000;
}
.snippet-editor .autocomplete {
  max-height: 220px;
  overflow-x: hidden;
  overflow-y: auto;
}
.snippet-editor .autocomplete-item {
  color: #1f2328;
  font-size: 14px;
  padding: 6px 14px;
}
.snippet-editor .autocomplete-item:hover {
  background-color: #f6f8fa;
  color: #1f2328;
}

/* Highlight palette - applies both to legend swatches and CM lines */
.snippet-editor .license-line {
  background-color: rgba(31, 136, 61, 0.12);
}
.snippet-editor .keyword-line {
  background-color: rgba(191, 135, 0, 0.14);
}
.snippet-editor .cm-line.license-line {
  box-shadow: inset 3px 0 0 #1f883d;
}
.snippet-editor .cm-line.keyword-line {
  box-shadow: inset 3px 0 0 #bf8700;
}
.snippet-editor .cm-line.license-line.keyword-line {
  box-shadow:
    inset 3px 0 0 #1f883d,
    inset 6px 0 0 #bf8700;
}
.snippet-editor .cm-line.found-pattern {
  cursor: help;
}

/* Hover tooltip card */
.cavil-pattern-tip {
  background: #ffffff;
  border: 1px solid #d0d7de;
  border-radius: 6px;
  box-shadow: 0 8px 24px rgba(140, 149, 159, 0.2);
  color: #1f2328;
  font-size: 12px;
  max-width: 360px;
  min-width: 220px;
  overflow: hidden;
}
.cavil-pattern-tip-loading,
.cavil-pattern-tip-error {
  padding: 10px 12px;
  color: #57606a;
}
.cavil-pattern-tip-error {
  color: #cf222e;
}
.cavil-pattern-tip-card {
  border-bottom: 1px solid #eaeef2;
}
.cavil-pattern-tip-card:last-child {
  border-bottom: 0;
}
.cavil-pattern-tip-header {
  align-items: center;
  background: #f6f8fa;
  border-bottom: 1px solid #eaeef2;
  display: flex;
  gap: 8px;
  justify-content: space-between;
  padding: 6px 10px;
}
.cavil-pattern-tip-title {
  font-weight: 600;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.cavil-pattern-tip-risk {
  background: #ddf4ff;
  border-radius: 10px;
  color: #0969da;
  font-size: 10px;
  font-weight: 600;
  padding: 1px 8px;
  text-transform: uppercase;
}
.cavil-pattern-tip-risk.risk-5,
.cavil-pattern-tip-risk.risk-6,
.cavil-pattern-tip-risk.risk-7 {
  background: #fff8c5;
  color: #9a6700;
}
.cavil-pattern-tip-risk.risk-8,
.cavil-pattern-tip-risk.risk-9 {
  background: #ffebe9;
  color: #cf222e;
}
.cavil-pattern-tip-preview {
  background: #f6f8fa;
  border: 0;
  color: #1f2328;
  font-family: monospace, monospace;
  font-size: 11px;
  line-height: 1.4;
  margin: 0;
  max-height: 140px;
  overflow: auto;
  padding: 8px 10px;
  white-space: pre-wrap;
  word-break: break-word;
}
.cavil-pattern-tip-footer {
  padding: 6px 10px;
  text-align: right;
}
.cavil-pattern-tip-footer a {
  color: #0969da;
  text-decoration: none;
}
.cavil-pattern-tip-footer a:hover {
  text-decoration: underline;
}

.snippet-editor .closest-container {
  margin-top: 1rem;
  margin-bottom: 3rem;
}
.snippet-editor .closest-header {
  background-color: rgb(246, 248, 250);
  border: 1px solid rgb(208, 215, 222);
  border-radius: 0.25rem 0.25rem 0 0;
  font-size: 13px;
  line-height: 20px;
  padding: 10px;
}
.snippet-editor .closest-header a {
  color: #212529;
  text-decoration: none;
}
.snippet-editor .closest-header a:hover {
  text-decoration: underline;
}
.snippet-editor .closest-source {
  border: 1px solid #dfe2e5 !important;
  border-top: 0 !important;
  border-bottom: 0 !important;
}
.snippet-editor .closest-source pre {
  font-family: monospace;
  padding: 0;
  margin: 0;
  font-size: 12px;
  line-height: 20px;
  color: rgba(27, 31, 35, 0.3);
  border: 0 !important;
  padding-left: 0.5em;
  color: #24292e;
  margin-left: 0.5em;
  white-space: -moz-pre-wrap;
  white-space: -o-pre-wrap;
  white-space: pre-wrap;
  word-wrap: break-word;
  word-break: break-all;
}
.snippet-editor .closest-footer {
  border: 1px solid rgb(208, 215, 222);
  border-top: 0;
  border-radius: 0 0 0.25rem 0.25rem;
  font-size: 13px;
  line-height: 20px;
  padding: 10px;
}
</style>
