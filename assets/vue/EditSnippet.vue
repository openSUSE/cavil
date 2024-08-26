<template>
  <div v-if="patternText === null"><i class="fas fa-sync fa-spin"></i> Loading snippet...</div>
  <div v-else>
    <div v-if="hasContributorRole === false && hasAdminRole === false" class="alert alert-info">
      There is no license pattern for this snippet yet. You do not have the necessary permissions to propose new license
      patterns. To change this contact an administrator and request the "contributor" role.
    </div>
    <div v-else-if="hasAdminRole === false" class="alert alert-info">
      There is no license pattern for this snippet yet, you are welcome to submit a proposal. An administrator will
      review it and decide if it should be added. However, you may only use existing licenses and risk assessments.
    </div>
    <div v-if="this.package !== null" class="row">
      <div class="col mb-3">
        The example shown here is from <a :href="this.package.packageUrl">{{ this.package.name }}</a
        >.
      </div>
    </div>
    <form :action="this.decisionUrl" method="POST">
      <input type="hidden" name="package" :value="this.package.id" v-if="this.package !== null" />
      <input type="hidden" name="highlighted-keywords" :value="this.highlightedKeywords" />
      <input type="hidden" name="highlighted-licenses" :value="this.highlightedLicenses" />
      <input type="hidden" name="edited" :value="this.edited" />
      <input type="hidden" name="hash" :value="this.hash" />
      <input type="hidden" name="from" :value="this.from" />
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
          <div id="patternHelp" class="form-text">
            Keyword patterns within the snippet are highlighted and you can reach them by clicking on the line number.
            Use expressions like <code>$SKIP5</code> to skip up to a certain number of words in your pattern. The
            expression <code>$SKIP19</code> represents the upper limit of the matching engine (which will be higher than
            19), and simply skips as many words as possible.
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
          <div href="#" id="patternHelp" class="form-text">
            Auto-completed license names will also predict the risk value.
            <a
              data-bs-html="true"
              data-bs-toggle="popover"
              data-bs-trigger="hover focus"
              data-bs-title="Standard Risks"
              :data-bs-content="riskHtml"
            >
              <i class="fas fa-question-circle"></i>
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
        <div class="col mb-3">
          <span v-if="hasAdminRole === true">
            <button name="create-pattern" type="submit" value="1" class="btn btn-primary mb-2">Create Pattern</button>
            &nbsp;
          </span>
          <button
            v-if="hasContributorRole === true"
            name="propose-pattern"
            type="submit"
            value="1"
            class="btn btn-success mb-2"
          >
            Propose Pattern
          </button>
          <span v-if="hasContributorRole === true && this.hash !== null && this.from !== null">
            &nbsp;
            <button name="propose-ignore" type="submit" value="1" class="btn btn-danger mb-2">Propose Ignore</button>
          </span>
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
    </form>
  </div>
</template>

<script>
import {setupPopoverDelayed} from './helpers/links.js';
import {getParams} from './helpers/params.js';
import UserAgent from '@mojojs/user-agent';
import CodeMirror from 'codemirror';

export default {
  name: 'EditSnippet',
  data() {
    const params = getParams();

    return {
      closest: null,
      closestUrl: '/snippet/closest',
      decisionUrl: `/snippet/decision/${this.currentSnippet}`,
      edited: '0',
      editor: null,
      from: params.from ?? null,
      hash: params.hash ?? null,
      highlightedKeywords: '',
      highlightedLicenses: '',
      keywords: {},
      license: '',
      licenseFocused: false,
      licenses: {},
      licenseOptions: {
        exportRestricted: false,
        patent: false,
        risk: 1,
        trademark: false
      },
      matches: {},
      package: null,
      patternText: '',
      results: [],
      riskHtml:
        '<b>Low risk licenses (auto-accepted)</b><br>' +
        '<b>0:</b> Public Domain<br>' +
        '<b>1:</b> MIT, BSD-2-clause<br>' +
        '<b>2:</b> GPL-2.0-or-later, Artistic-2.0<br>' +
        '<b>3:</b> Apache-2.0, AGPL-3.0-or-later<br>' +
        '<b>Higher risk licenses</b><br>' +
        '<b>4:</b> CDDL-1.0, MPL-1.1, Any EULA<br>' +
        '<b>5:</b> CC-BY-NC-ND-1.0, SSPL-1.0<br>' +
        '<b>6:</b> Any Proprietary<br>' +
        '<b>Unknown risk (reserved)</b><br>' +
        '<b>9:</b> Keyword patterns',
      snippetUrl: `/snippet/meta/${this.currentSnippet}`,
      startLine: null,
      suggestions: [],
      ua: new UserAgent({baseURL: window.location.href})
    };
  },
  async mounted() {
    this.setupPopover();
    await this.getSnippet();
    this.setupCodeMirror();
    await this.getClosest();
  },
  methods: {
    autocomplete() {
      const license = this.license;
      if (license === '') {
        this.results = this.suggestions;
      } else {
        this.results = this.suggestions.filter(name => name.toLowerCase().includes(license.toLowerCase()));
      }
    },
    fillLicense(result) {
      this.$refs.license.blur();
      this.license = result;
      if (this.licenses[result] !== undefined) this.licenseOptions = this.licenses[result];
      this.results = this.suggestions;
      this.licenseFocused = false;
    },
    async getClosest() {
      const text = this.editor.getValue();
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
      if (this.package !== null) this.package.packageUrl = `/reviews/details/${this.package.id}`;
      this.patternText = snippet.text;
      this.startLine = snippet.sline;
      this.matches = snippet.matches;
      this.keywords = snippet.keywords;
      this.licenses = data.licenses;
      this.suggestions = Object.keys(this.licenses);
      this.results = this.suggestions;

      if (data.closest !== null) this.fillLicense(data.closest);
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
    setupCodeMirror() {
      const cm = CodeMirror.fromTextArea(this.$refs.patternText, {
        firstLineNumber: this.startLine,
        lineNumbers: true,
        theme: 'neo'
      });

      cm.on('change', () => {
        this.edited = '1';
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
          window.location.href = `/licenses/edit_pattern/${matches[1]}`;
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
    setupPopover() {
      setupPopoverDelayed();
    }
  }
};
</script>

<style>
.CodeMirror {
  border: 1px solid #dee2e6;
  border-radius: 5px;
  height: 600px;
  padding: 5px;
}
.autocomplete {
  height: 220px;
  overflow-x: hidden;
  overflow-y: scroll;
}
.autocomplete-container {
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
.autocomplete-item:hover {
  background-color: rgba(13, 110, 253, 0.25);
}
.keyword-line {
  background-color: #fdd !important;
}
.license-line {
  background-color: #dfd !important;
}

.closest-container {
  margin-top: 1rem;
  margin-bottom: 3rem;
}
.closest-header {
  background-color: rgb(246, 248, 250);
  border: 1px solid rgb(208, 215, 222);
  border-radius: 0.25rem 0.25rem 0 0;
  font-size: 13px;
  line-height: 20px;
  padding: 10px;
}
.closest-header a {
  color: #212529;
  text-decoration: none;
}
.closest-header a:hover {
  text-decoration: underline;
}
.closest-source {
  border: 1px solid #dfe2e5 !important;
  border-top: 0 !important;
  border-bottom: 0 !important;
}
.closest-source pre {
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
.closest-footer {
  border: 1px solid rgb(208, 215, 222);
  border-top: 0;
  border-radius: 0 0 0.25rem 0.25rem;
  font-size: 13px;
  line-height: 20px;
  padding: 10px;
}
</style>
