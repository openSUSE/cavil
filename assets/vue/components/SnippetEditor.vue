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
      <div v-if="mode === 'page' && this.package !== null" class="row">
        <div class="col mb-3">
          The example shown here is from the file <a :href="this.package.fileUrl">{{ this.package.file }}</a> in the
          package <a :href="this.package.packageUrl">{{ this.package.name }}</a
          >.
        </div>
      </div>
      <div class="snippet-editor-form">
        <div class="snippet-editor-tabs" role="tablist">
          <button
            type="button"
            class="snippet-editor-tab"
            :class="{active: activeTab === 'edit'}"
            role="tab"
            :aria-selected="activeTab === 'edit'"
            data-tab="edit"
            @click="setActiveTab('edit')"
          >
            <i class="fa-solid fa-pen-to-square"></i> Edit
          </button>
          <button
            type="button"
            class="snippet-editor-tab"
            :class="{active: activeTab === 'closest'}"
            role="tab"
            :aria-selected="activeTab === 'closest'"
            data-tab="closest"
            :disabled="closest === null"
            @click="setActiveTab('closest')"
          >
            <i class="fa-solid fa-magnifying-glass"></i>
            Closest match
            <span v-if="closest !== null" class="snippet-editor-tab-badge">{{ closest.similarity }}%</span>
          </button>
        </div>
        <div class="snippet-editor-tab-content">
          <div
            class="snippet-editor-tab-pane"
            :class="{'is-active': activeTab === 'edit'}"
            :aria-hidden="activeTab !== 'edit'"
          >
            <div class="row">
              <div class="col mb-3">
                <label class="form-label" for="pattern">Snippet</label>
                <div ref="editorHost" class="snippet-editor-host">
                  <div class="snippet-editor-tools">
                    <button
                      type="button"
                      class="snippet-editor-tool-btn"
                      data-action="smart-edit"
                      :disabled="smartEditBusy"
                      :title="smartEditBusy ? 'Smart edit in progress…' : 'Smart edit (auto-trim to core pattern)'"
                      aria-label="Smart edit"
                      @click="smartEdit"
                    >
                      <i v-if="smartEditBusy" class="fa-solid fa-rotate fa-spin"></i>
                      <i v-else class="fa-solid fa-wand-magic-sparkles"></i>
                    </button>
                    <button
                      type="button"
                      class="snippet-editor-tool-btn"
                      data-action="restore-original"
                      :disabled="!canRestoreOriginal"
                      title="Restore original snippet"
                      aria-label="Restore original snippet"
                      @click="restoreOriginal"
                    >
                      <i class="fa-solid fa-rotate-left"></i>
                    </button>
                  </div>
                </div>
                <textarea
                  ref="patternText"
                  v-model="patternText"
                  class="mono-text form-control snippet-editor-textarea"
                  id="pattern"
                  name="pattern"
                  rows="20"
                ></textarea>
                <div id="patternHelp" class="snippet-editor-hints">
                  <span class="snippet-editor-hints-item">
                    <span class="snippet-editor-hints-swatch keyword-line"></span> keyword
                  </span>
                  <span class="snippet-editor-hints-item">
                    <span class="snippet-editor-hints-swatch license-line"></span> existing pattern
                  </span>
                  <span class="snippet-editor-hints-item">
                    <code>$SKIPn</code> skips up to n words at this position
                  </span>
                </div>
              </div>
            </div>
            <div class="row">
              <div class="col mb-3">
                <label class="form-label" for="license">License</label>
                <div class="snippet-editor-autocomplete-anchor">
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
          <div
            class="snippet-editor-tab-pane snippet-editor-closest-pane"
            :class="{'is-active': activeTab === 'closest'}"
            :aria-hidden="activeTab !== 'closest'"
          >
            <ClosestPattern :pattern="patternText" @loaded="onClosestLoaded" />
          </div>
        </div>
        <div class="row">
          <div class="col mb-3 snippet-editor-actions">
            <div class="snippet-editor-action-buttons">
              <div v-if="availableActions.length > 0" class="btn-group">
                <button
                  type="button"
                  class="btn btn-success"
                  :data-action="availableActions[0]"
                  @click="emitAction(availableActions[0])"
                >
                  {{ actionLabel(availableActions[0]) }}
                </button>
                <button
                  v-if="availableActions.length > 1"
                  type="button"
                  class="btn snippet-editor-neutral"
                  :data-action="availableActions[1]"
                  @click="emitAction(availableActions[1])"
                >
                  {{ actionLabel(availableActions[1]) }}
                </button>
                <template v-if="availableActions.length > 2">
                  <button
                    type="button"
                    class="btn snippet-editor-neutral dropdown-toggle dropdown-toggle-split"
                    data-bs-toggle="dropdown"
                    aria-expanded="false"
                    aria-label="More actions"
                  ></button>
                  <ul class="dropdown-menu">
                    <li v-for="action in availableActions.slice(2)" :key="action">
                      <a class="dropdown-item" href="#" :data-action="action" @click.prevent="emitAction(action)">
                        {{ actionLabel(action) }}
                      </a>
                    </li>
                  </ul>
                </template>
              </div>
              <button
                v-if="mode === 'inline'"
                type="button"
                class="btn snippet-editor-neutral"
                data-action="cancel"
                @click="$emit('cancel')"
              >
                Cancel
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script>
import ClosestPattern from './ClosestPattern.vue';
import {setupPopoverDelayed} from '../helpers/links.js';
import {EditorState, StateEffect, StateField} from '@codemirror/state';
import {Decoration, EditorView, hoverTooltip} from '@codemirror/view';
import UserAgent from '@mojojs/user-agent';

const setDecoLinesEffect = StateEffect.define();

export default {
  name: 'SnippetEditor',
  components: {ClosestPattern},
  props: {
    snippetId: {type: Number, required: true},
    hash: {type: String, default: null},
    from: {type: String, default: null},
    hasContributorRole: {type: Boolean, default: false},
    hasAdminRole: {type: Boolean, default: false},
    mode: {type: String, default: 'page'},
    initial: {type: Object, default: null}
  },
  emits: ['submit', 'cancel'],
  data() {
    return {
      activeTab: 'edit',
      closest: null,
      decorationsField: null,
      edited: '0',
      editor: null,
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
      originalDecorations: null,
      originalSnippetText: null,
      package: null,
      patternMeta: new Map(),
      patternMetaPromises: new Map(),
      patternText: null,
      results: [],
      smartEditBusy: false,
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
    this.setupCodeMirror();
  },
  beforeUnmount() {
    if (this.editor) {
      this.editor.destroy();
      this.editor = null;
    }
  },
  computed: {
    canRestoreOriginal() {
      return this.originalSnippetText !== null && this.patternText !== this.originalSnippetText;
    },
    availableActions() {
      const hasContext = this.hash !== null && this.from !== null;
      const isUnmodified = this.edited === '0';
      const canPropose = this.hasAdminRole || this.hasContributorRole;
      const actions = [];

      // Primary (green) slot: immediate-create for admins, propose-create otherwise.
      if (this.hasAdminRole) actions.push('create-pattern');
      else if (this.hasContributorRole) actions.push('propose-pattern');

      // Secondary (neutral) slot: immediate-ignore for admins with context, propose-ignore otherwise.
      if (this.hasAdminRole && hasContext) actions.push('create-ignore');
      else if (this.hasContributorRole && isUnmodified) actions.push('propose-ignore');

      // Shared dropdown: weaker proposal variants (admins see them too, since
      // their permissions are a superset of contributors') and the admin-only
      // "No Legal Text" action at the end.
      if (this.hasAdminRole) actions.push('propose-pattern');
      if (canPropose && hasContext && isUnmodified) actions.push('propose-missing');
      if (this.hasAdminRole && isUnmodified) actions.push('propose-ignore');
      if (this.hasAdminRole && hasContext) actions.push('mark-non-license');

      return actions;
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
    onClosestLoaded(closest) {
      this.closest = closest;
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
      if (this.editor) this.editor.requestMeasure();
    },
    async setActiveTab(tab) {
      if (tab === 'closest' && this.closest === null) return;
      this.activeTab = tab;
      if (tab === 'edit') {
        await this.$nextTick();
        this.refreshEditor();
      }
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

      this.originalDecorations = {matchLineSet, keywordLineSet, idsByLine};
      this.originalSnippetText = this.patternText ?? '';

      const buildRanges = (state, mSet, kSet, idsMap) => {
        const ranges = [];
        const sorted = [...idsMap.keys()].sort((a, b) => a - b);
        for (const lineIdx of sorted) {
          const cmLineNo = lineIdx + 1;
          if (cmLineNo < 1 || cmLineNo > state.doc.lines) continue;
          const line = state.doc.line(cmLineNo);
          const classes = ['found-pattern'];
          if (mSet[lineIdx]) classes.push('license-line');
          if (kSet[lineIdx]) classes.push('keyword-line');
          ranges.push(
            Decoration.line({
              attributes: {
                class: classes.join(' '),
                'data-pattern-ids': (idsMap.get(lineIdx) ?? []).join(' ')
              }
            }).range(line.from)
          );
        }
        return Decoration.set(ranges, true);
      };

      const decoField = StateField.define({
        create: state => buildRanges(state, matchLineSet, keywordLineSet, idsByLine),
        update: (decos, tr) => {
          for (const effect of tr.effects) {
            if (effect.is(setDecoLinesEffect)) {
              const v = effect.value;
              return buildRanges(tr.state, v.matchLineSet, v.keywordLineSet, v.idsByLine);
            }
          }
          return tr.docChanged ? decos.map(tr.changes) : decos;
        },
        provide: f => EditorView.decorations.from(f)
      });
      this.decorationsField = decoField;

      const baseTheme = EditorView.theme({
        '&': {fontSize: '13px'},
        '.cm-scroller': {fontFamily: 'monospace, monospace', overflow: 'auto'}
      });

      const state = EditorState.create({
        doc: this.patternText ?? '',
        extensions: [
          decoField,
          EditorView.lineWrapping,
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
        this.getHighlightedLines();
      }
    },
    async smartEdit() {
      if (!this.editor || this.smartEditBusy) return;
      this.smartEditBusy = true;
      try {
        const res = await this.ua.get(`/snippet/smart_edit/${this.snippetId}`);
        if (!res.isSuccess) return;
        const data = await res.json();
        const pattern = data.pattern;
        if (typeof pattern !== 'string') return;
        const currentDoc = this.editor.state.doc.toString();
        if (pattern === currentDoc) return;

        const offset = data.start_line - this.startLine;
        const od = this.originalDecorations;
        const shiftSet = src => {
          const out = {};
          for (const k of Object.keys(src)) {
            const i = parseInt(k) - offset;
            if (i >= 0) out[i] = true;
          }
          return out;
        };
        const shiftMap = src => {
          const out = new Map();
          for (const [k, v] of src.entries()) {
            const i = k - offset;
            if (i >= 0) out.set(i, v);
          }
          return out;
        };
        const trimmedDecorations = {
          matchLineSet: shiftSet(od.matchLineSet),
          keywordLineSet: shiftSet(od.keywordLineSet),
          idsByLine: shiftMap(od.idsByLine)
        };

        this.editor.dispatch({
          changes: {from: 0, to: this.editor.state.doc.length, insert: pattern},
          effects: setDecoLinesEffect.of(trimmedDecorations),
          selection: {anchor: 0}
        });
      } finally {
        this.smartEditBusy = false;
      }
    },
    restoreOriginal() {
      this.editor.dispatch({
        changes: {from: 0, to: this.editor.state.doc.length, insert: this.originalSnippetText},
        effects: setDecoLinesEffect.of(this.originalDecorations),
        selection: {anchor: 0}
      });
      this.editor.focus();
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
  position: relative;
}
.snippet-editor .snippet-editor-tools {
  display: flex;
  gap: 4px;
  position: absolute;
  right: 8px;
  top: 8px;
  z-index: 5;
}
.snippet-editor .snippet-editor-tool-btn {
  align-items: center;
  background: rgba(255, 255, 255, 0.92);
  border: 1px solid #d0d7de;
  border-radius: 6px;
  box-shadow: 0 1px 2px rgba(31, 35, 40, 0.08);
  color: #1f2328;
  cursor: pointer;
  display: inline-flex;
  font-size: 13px;
  height: 28px;
  justify-content: center;
  padding: 0;
  transition:
    background-color 0.15s,
    box-shadow 0.15s,
    color 0.15s;
  width: 28px;
}
.snippet-editor .snippet-editor-tool-btn:hover:not(:disabled) {
  background: #ffffff;
  box-shadow: 0 2px 4px rgba(31, 35, 40, 0.12);
  color: #0969da;
}
.snippet-editor .snippet-editor-tool-btn:focus {
  border-color: #0969da;
  box-shadow: 0 0 0 3px rgba(9, 105, 218, 0.3);
  color: #0969da;
  outline: none;
}
.snippet-editor .snippet-editor-tool-btn:disabled {
  cursor: not-allowed;
  opacity: 0.5;
}
.snippet-editor .snippet-editor-host .cm-editor {
  height: auto;
  max-height: 70vh;
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
  align-items: center;
  color: #57606a;
  column-gap: 16px;
  display: flex;
  flex-wrap: wrap;
  font-size: 12px;
  margin-top: 6px;
  row-gap: 4px;
}
.snippet-editor .form-text {
  color: #57606a;
  font-size: 12px;
  margin-top: 6px;
}
.snippet-editor-hints-item {
  align-items: center;
  display: inline-flex;
  gap: 6px;
  white-space: nowrap;
}
.snippet-editor-hints code {
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
  height: 10px;
  vertical-align: middle;
  width: 18px;
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
.snippet-editor .snippet-editor-neutral {
  background-color: #f6f8fa;
  border: 1px solid rgba(31, 35, 40, 0.15);
  color: #1f2328;
  font-size: 14px;
  font-weight: 500;
  line-height: 20px;
  padding: 5px 16px;
}
.snippet-editor .snippet-editor-neutral:hover {
  background-color: #eef0f3;
  border-color: rgba(31, 35, 40, 0.15);
  color: #1f2328;
}
.snippet-editor .snippet-editor-neutral:focus {
  background-color: #f6f8fa;
  border-color: rgba(31, 35, 40, 0.15);
  box-shadow: 0 0 0 3px rgba(9, 105, 218, 0.3);
  color: #1f2328;
  outline: none;
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

/* Attributes row */
.snippet-editor .snippet-editor-attributes {
  align-items: flex-start;
  display: flex;
  flex-wrap: wrap;
  gap: 24px;
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
.snippet-editor .dropdown-toggle-split {
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
.snippet-editor .snippet-editor-autocomplete-anchor {
  position: relative;
}
.snippet-editor .autocomplete-container {
  background: #ffffff;
  border: 1px solid #d0d7de;
  border-radius: 6px;
  box-shadow: 0 8px 24px rgba(140, 149, 159, 0.2);
  cursor: pointer;
  left: 0;
  margin: 4px 0 0;
  padding: 4px 0;
  position: absolute;
  right: 0;
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

/* Hover tooltip card - GitHub-style overlay */
.cm-tooltip.cm-tooltip-hover:has(.cavil-pattern-tip) {
  background: transparent;
  border: 0;
  padding: 0;
}
.cavil-pattern-tip {
  background: #ffffff;
  border: 1px solid #d0d7de;
  border-radius: 8px;
  box-shadow:
    0 1px 3px rgba(31, 35, 40, 0.08),
    0 8px 24px rgba(66, 74, 83, 0.12);
  color: #1f2328;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Noto Sans', Helvetica, Arial, sans-serif;
  font-size: 12px;
  line-height: 1.5;
  max-width: 380px;
  min-width: 240px;
  overflow: hidden;
}
.cavil-pattern-tip-loading,
.cavil-pattern-tip-error {
  align-items: center;
  color: #59636e;
  display: flex;
  gap: 8px;
  padding: 12px 14px;
}
.cavil-pattern-tip-error {
  color: #cf222e;
}
.cavil-pattern-tip-card {
  border-top: 1px solid #d1d9e0b3;
  padding: 12px 14px;
}
.cavil-pattern-tip-card:first-child {
  border-top: 0;
}
.cavil-pattern-tip-header {
  align-items: center;
  display: flex;
  gap: 8px;
  justify-content: space-between;
  margin-bottom: 8px;
}
.cavil-pattern-tip-title {
  color: #1f2328;
  font-size: 13px;
  font-weight: 600;
  letter-spacing: -0.05px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.cavil-pattern-tip-risk {
  /* Matches the badge palette used elsewhere in the report UI:
     0-4 green, 5 yellow, 6-8 red, 9 black. */
  border: 1px solid transparent;
  border-radius: 2em;
  font-size: 11px;
  font-weight: 500;
  line-height: 18px;
  padding: 0 7px;
  white-space: nowrap;
  background: rgba(31, 136, 61, 0.1);
  color: #1a7f37;
  border-color: rgba(31, 136, 61, 0.2);
}
.cavil-pattern-tip-risk.risk-5 {
  background: rgba(154, 103, 0, 0.1);
  color: #9a6700;
  border-color: rgba(154, 103, 0, 0.2);
}
.cavil-pattern-tip-risk.risk-6,
.cavil-pattern-tip-risk.risk-7,
.cavil-pattern-tip-risk.risk-8 {
  background: rgba(207, 34, 46, 0.1);
  color: #cf222e;
  border-color: rgba(207, 34, 46, 0.2);
}
.cavil-pattern-tip-risk.risk-9 {
  background: #1f2328;
  color: #ffffff;
  border-color: #1f2328;
}
.cavil-pattern-tip-preview {
  background: #f6f8fa;
  border: 1px solid #d1d9e0b3;
  border-radius: 6px;
  color: #1f2328;
  font-family:
    ui-monospace,
    SFMono-Regular,
    SF Mono,
    Menlo,
    Consolas,
    Liberation Mono,
    monospace;
  font-size: 11px;
  line-height: 1.45;
  margin: 0;
  max-height: 140px;
  overflow: auto;
  padding: 8px 10px;
  white-space: pre-wrap;
  word-break: break-word;
}
.cavil-pattern-tip-footer {
  margin-top: 10px;
}
.cavil-pattern-tip-footer a {
  color: #0969da;
  font-size: 12px;
  font-weight: 500;
  text-decoration: none;
}
.cavil-pattern-tip-footer a:hover {
  text-decoration: underline;
}

.snippet-editor-tabs {
  border-bottom: 1px solid #d0d7de;
  display: flex;
  gap: 4px;
  margin-bottom: 16px;
}
.snippet-editor-tab {
  align-items: center;
  background: transparent;
  border: 1px solid transparent;
  border-bottom: 0;
  border-radius: 6px 6px 0 0;
  color: #57606a;
  cursor: pointer;
  display: inline-flex;
  font-size: 13px;
  font-weight: 500;
  gap: 6px;
  line-height: 1;
  margin-bottom: -1px;
  padding: 8px 14px;
  transition:
    background-color 0.15s,
    color 0.15s;
}
.snippet-editor-tab:hover:not(:disabled):not(.active) {
  background: #f3f5f7;
  color: #1f2328;
}
.snippet-editor-tab.active {
  background: #ffffff;
  border-color: #d0d7de;
  color: #1f2328;
  font-weight: 600;
}
.snippet-editor-tab:disabled {
  color: #8c959f;
  cursor: not-allowed;
}
.snippet-editor-tab-badge {
  background: #ddf4ff;
  border-radius: 10px;
  color: #0969da;
  font-size: 11px;
  font-weight: 600;
  margin-left: 2px;
  padding: 1px 7px;
}
.snippet-editor-tab:disabled .snippet-editor-tab-badge {
  background: #eaeef2;
  color: #8c959f;
}
.snippet-editor-tab-content {
  position: relative;
}
.snippet-editor-tab-pane {
  min-width: 0;
  visibility: hidden;
}
.snippet-editor-tab-pane.is-active {
  visibility: visible;
}
.snippet-editor-closest-pane {
  position: absolute;
  inset: 0;
  overflow-y: auto;
}
</style>
