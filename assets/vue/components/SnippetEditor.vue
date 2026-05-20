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
            <textarea
              ref="patternText"
              v-model="patternText"
              class="mono-text form-control"
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
                  <dt>Line number</dt>
                  <dd>Click to open the pattern that matched on that line</dd>
                </template>
              </dl>
            </div>
          </div>
        </div>
        <div class="row">
          <div class="col mb-3">
            <label class="fomr-label" for="license">License</label>
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
          <div class="col-lg-2 mb-3">
            <div class="form-floating">
              <select v-model="licenseOptions.risk" name="risk" id="risk" class="form-control">
                <option>0</option>
                <option>1</option>
                <option>2</option>
                <option>3</option>
                <option>4</option>
                <option>5</option>
                <option>6</option>
                <option>9</option>
              </select>
              <label for="risk" class="form-label">Risk</label>
            </div>
          </div>
          <div class="col-lg-2">
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
          </div>
          <div class="col-lg-2">
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
import UserAgent from '@mojojs/user-agent';
import CodeMirror from 'codemirror';

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
      this.editor.toTextArea();
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
      const text = this.editor ? this.editor.getValue() : this.patternText;
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
      this.licenseOptions.export_restricted =
        initial.export_restricted === '1' || initial.export_restricted === true;
      if (initial.edited !== undefined) this.edited = String(initial.edited);
      if (initial['highlighted-keywords'] !== undefined) {
        this.highlightedKeywords = initial['highlighted-keywords'];
      }
      if (initial['highlighted-licenses'] !== undefined) {
        this.highlightedLicenses = initial['highlighted-licenses'];
      }
    },
    getHighlightedLines() {
      const cm = this.editor;
      const count = cm.lineCount();
      const keywordLines = [];
      const licenseLines = [];
      for (let i = 0; i < count; i++) {
        const line = cm.getLineHandle(i);
        const bgClass = line.bgClass ?? '';
        if (bgClass.match('keyword-line')) keywordLines.push(i);
        if (bgClass.match('license-line')) licenseLines.push(i);
      }
      this.highlightedKeywords = keywordLines.join(',');
      this.highlightedLicenses = licenseLines.join(',');
    },
    refreshEditor() {
      // Modal host signals the modal is fully shown. In batch mode this is our
      // cue that the textarea has its real dimensions, so it's now safe to
      // attach CodeMirror (or refresh it if it was already attached).
      this.editorReady = true;
      if (this.editor) {
        this.editor.refresh();
        return;
      }
      this.maybeSetupCodeMirror();
    },
    maybeSetupCodeMirror() {
      if (!this.editorReady) return;
      this.setupCodeMirror();
    },
    setupCodeMirror() {
      if (this.editor || !this.$refs.patternText) return;
      const cm = CodeMirror.fromTextArea(this.$refs.patternText, {
        firstLineNumber: this.startLine,
        lineNumbers: true,
        theme: 'neo'
      });

      cm.on('change', () => {
        this.edited = '1';
        this.patternText = cm.getValue();
      });
      cm.on('blur', () => {
        this.getClosest();
        this.getHighlightedLines();
      });
      cm.on('gutterClick', (cm, n) => {
        const info = cm.lineInfo(n);
        const bgClass = info.bgClass ?? '';
        if (bgClass.includes('found-pattern') === true) {
          const matches = bgClass.match(/pattern-(\d+)/);
          window.open(`/licenses/edit_pattern/${matches[1]}`, '_blank', 'noopener');
        }
      });

      for (const [line, pattern] of Object.entries(this.matches)) {
        cm.addLineClass(parseInt(line), 'background', `license-line found-pattern pattern-${pattern}`);
      }

      for (const [line, pattern] of Object.entries(this.keywords)) {
        cm.addLineClass(parseInt(line), 'background', `keyword-line found-pattern pattern-${pattern}`);
      }

      this.editor = cm;
      this.getHighlightedLines();
    },
    emitAction(action) {
      if (this.editor) {
        this.patternText = this.editor.getValue();
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
.snippet-editor .CodeMirror {
  border: 1px solid #dee2e6;
  border-radius: 5px;
  height: 600px;
  padding: 5px;
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
.snippet-editor .autocomplete {
  height: 220px;
  overflow-x: hidden;
  overflow-y: scroll;
}
.snippet-editor .autocomplete-container {
  border: 1px solid #dee2e6;
  border-top: 0;
  border-radius: 0 0 5px 5px;
  cursor: pointer;
  padding: 3px;
  padding-top: 8px;
  padding-right: 0;
  margin: 0;
  z-index: 1000;
}
.snippet-editor .autocomplete-item:hover {
  background-color: rgba(13, 110, 253, 0.25);
}
.snippet-editor .license-line {
  background-color: #dfd !important;
}
.snippet-editor .keyword-line {
  background-color: #fdd !important;
}
.snippet-editor span.keyword-line,
.snippet-editor span.license-line {
  padding: 0.25em;
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
