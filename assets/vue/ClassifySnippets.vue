<template>
  <div>
    <div class="row mt-3">
      <cavil-notice-panel v-if="hasClassifierRole === true" intro class="col-11">
        These snippets have been pre-processed by our machine learning model to decide if they are legal text or not.
        Legal text is highlighted in yellow. You can help us improve the model by voting the decisions up or down.
      </cavil-notice-panel>
      <cavil-notice-panel v-else intro class="col-11">
        These snippets have been pre-processed by our machine learning model to decide if they are legal text or not.
        Legal text is highlighted in yellow.
      </cavil-notice-panel>
    </div>
    <div class="row g-4">
      <div class="col-11">
        <form @submit.prevent>
          <div class="row g-4">
            <div class="col-lg-2">
              <div class="form-floating">
                <select v-model="params.confidence" @change="refreshPage()" class="form-control cavil-pkg-confidence">
                  <option value="100">Any</option>
                  <option value="95">95% or less</option>
                  <option value="90">90% or less</option>
                  <option value="80">80% or less</option>
                  <option value="70">70% or less</option>
                  <option value="50">50% or less</option>
                  <option value="30">30% or less</option>
                  <option value="20">20% or less</option>
                  <option value="10">10% or less</option>
                  <option value="5">5% or less</option>
                </select>
                <label class="form-label">Confidence</label>
              </div>
            </div>
            <div class="col-lg-2">
              <div class="form-floating">
                <select v-model="params.timeframe" @change="refreshPage()" class="form-control cavil-pkg-timeframe">
                  <option value="any">Any</option>
                  <option value="year">1 year</option>
                  <option value="month">1 month</option>
                  <option value="week">1 week</option>
                  <option value="day">1 day</option>
                  <option value="hour">1 hour</option>
                </select>
                <label class="form-label">Timeframe</label>
              </div>
            </div>
            <div class="col-lg-2">
              <div class="form-floating">
                <select
                  v-model="params.resolution"
                  @change="refreshPage()"
                  class="form-control cavil-snippet-resolution"
                >
                  <option value="any">Any</option>
                  <option value="unresolved">Unresolved</option>
                  <option value="fold">Folded</option>
                  <option value="clear">Cleared</option>
                  <option value="overlap">Overlap</option>
                  <option value="covered">Covered</option>
                </select>
                <label class="form-label">Resolution</label>
              </div>
            </div>
            <div class="col-lg-2">
              <div class="form-floating">
                <select v-model="params.order" @change="refreshPage()" class="form-control cavil-snippet-order">
                  <option value="occurrences">Occurrences</option>
                  <option value="packages">Packages</option>
                  <option value="risk">Risk</option>
                  <option value="recent">Recent</option>
                </select>
                <label class="form-label">Order</label>
              </div>
            </div>
            <div class="col-lg-2">
              <div class="form-check">
                <input
                  v-model="params.notLegal"
                  @change="refreshPage()"
                  type="checkbox"
                  class="form-check-input"
                  id="snippet-not-legal"
                />
                <label class="form-check-label" for="snippet-not-legal">Not legal text</label>
              </div>
              <div class="form-check">
                <input
                  v-model="params.isLegal"
                  @change="refreshPage()"
                  type="checkbox"
                  class="form-check-input"
                  id="snippet-is-legal"
                />
                <label class="form-check-label" for="snippet-is-legal">Is legal text</label>
              </div>
            </div>
            <div class="col-lg-2">
              <div class="form-check">
                <input
                  v-model="params.isClassified"
                  @change="refreshPage()"
                  type="checkbox"
                  class="form-check-input"
                  id="snippet-is-classified"
                />
                <label class="form-check-label" for="snippet-is-classified">Classified by AI</label>
              </div>
              <div class="form-check">
                <input
                  v-model="params.isApproved"
                  @change="refreshPage()"
                  type="checkbox"
                  class="form-check-input"
                  id="snippet-is-approved"
                />
                <label class="form-check-label" for="snippet-is-approved">Approved by a human</label>
              </div>
            </div>
          </div>
        </form>
      </div>
    </div>
    <div class="row g-4 mt-1">
      <div class="col-11">
        <form @submit.prevent>
          <div class="form-floating">
            <input
              v-model="params.search"
              @input="onSearchInput"
              type="text"
              class="form-control cavil-snippet-search"
              id="snippet-search"
              placeholder="Search snippet text"
            />
            <label class="form-label" for="snippet-search">Search text</label>
          </div>
        </form>
      </div>
    </div>
    <div v-if="snippets === null" class="row mt-3">
      <div class="col-11 text-center">
        <LegalLoading message="Loading snippets" size="small" />
      </div>
    </div>
    <div v-else-if="snippets.length > 0">
      <div v-for="snippet in snippets" :key="snippet.id" class="row snippet-container">
        <div class="col-11 snippet-file-container">
          <div class="snippet-file">
            <a v-if="snippet.filename !== null" :href="snippet.fileUrl" target="_blank">{{ snippet.filename }}</a>
            <a v-else>Unknown file</a>
            <span v-if="snippet.files === 2">, and 1 other file</span>
            <span v-else-if="snippet.files > 2">, and {{ snippet.files - 1 }} other files</span>
            <div class="float-end">
              <i v-if="snippet.embargoed === true" class="fa-solid fa-lock" title="Embargoed"></i>
              <i v-if="snippet.approved === true" class="fa-solid fa-circle-check ms-2" title="Approved by a human"></i>
            </div>
          </div>
          <div class="snippet-source">
            <table class="snippet">
              <tbody>
                <tr v-for="line in snippet.lines" :key="line.num" :class="getClassForSnippet(snippet)">
                  <td class="linenumber">{{ line.num }}</td>
                  <td class="code">{{ line.text }}</td>
                </tr>
              </tbody>
            </table>
          </div>
          <div class="snippet-footer">
            <div class="snippet-likelyness">
              <a :href="snippet.editUrl" target="_blank">
                <div v-if="snippet.license_name !== null">
                  <b>{{ snippet.likelyness }}%</b> similarity to <b>{{ snippet.license_name }}</b
                  >, estimated risk
                  {{ snippet.risk }}
                </div>
                <div v-else>No similarity to any known licenses</div>
              </a>
            </div>
            <div class="snippet-assessment float-end">
              <div v-if="snippet.classified === true && snippet.license === true">
                Is legal text, <b>{{ snippet.confidence }}%</b> confidence
              </div>
              <div v-else-if="snippet.classified === true">
                Not legal text, <b>{{ snippet.confidence }}%</b> confidence
              </div>
              <div v-else>Not yet classified by AI</div>
            </div>
          </div>
        </div>
        <div class="col-1 snippet-approval">
          <div v-if="hasClassifierRole === true" class="snippet-arrows">
            <div :class="getClassForArrow(snippet, true)">
              <a @click="approveSnippet(snippet, true)" href="javascript:;"
                ><i class="fa-solid fa-circle-chevron-up"></i
              ></a>
            </div>
            <div :class="getClassForArrow(snippet, false)">
              <a @click="approveSnippet(snippet, false)" href="javascript:;"
                ><i class="fa-solid fa-circle-chevron-down"></i
              ></a>
            </div>
          </div>
        </div>
      </div>
      <div v-if="loadingMore" class="text-center text-muted my-3">
        <LegalLoading message="Loading more snippets" size="small" />
      </div>
      <BackToTop />
    </div>
    <div v-else class="row mt-3">
      <p class="text-muted" id="snippets-empty">No snippets match these filters.</p>
    </div>
  </div>
</template>

<script>
import BackToTop from './components/BackToTop.vue';
import CavilNoticePanel from './components/CavilNoticePanel.vue';
import LegalLoading from './components/LegalLoading.vue';
import {fileViewUrl} from './helpers/links.js';
import {genParamWatchers, getParams} from './helpers/params.js';
import UserAgent from '@mojojs/user-agent';

export default {
  name: 'ClassifySnippets',
  components: {BackToTop, CavilNoticePanel, LegalLoading},
  data() {
    const params = getParams({
      confidence: 100,
      isClassified: true,
      isApproved: false,
      isLegal: true,
      notLegal: true,
      timeframe: 'any',
      resolution: 'any',
      order: 'recent',
      search: ''
    });

    return {
      params: {...params, before: 0, offset: 0},
      snippets: null,
      snippetUrl: '/snippets/meta',
      hasMore: false,
      loadingMore: false
    };
  },
  mounted() {
    window.addEventListener('scroll', this.handleScroll);
    this.getSnippets();
  },
  beforeDestroy() {
    window.removeEventListener('scroll', this.handleScroll);
  },
  methods: {
    async approveSnippet(snippet, approved) {
      snippet.buttonPressed = approved;
      const ua = new UserAgent({baseURL: window.location.href});
      await ua.post(`/snippets/${snippet.id}`, {
        query: {license: approved === true ? snippet.license : !snippet.license}
      });
      snippet.approved = true;
    },
    async getSnippets() {
      const query = this.params;
      const ua = new UserAgent({baseURL: window.location.href});
      const res = await ua.get(this.snippetUrl, {query});
      const data = await res.json();

      const snippets = data.snippets;
      this.hasMore = data.hasMore === true;

      for (const snippet of snippets) {
        snippet.buttonPressed = null;
        snippet.fileUrl = snippet.filename == null ? null : fileViewUrl(snippet.filepackage, snippet.filename);
        snippet.editUrl = `/snippet/edit/${snippet.id}`;
        let num = snippet.sline ?? 1;
        const lines = [];
        for (const line of snippet.text.split('\n')) {
          lines.push({num: num++, text: line});
        }
        snippet.lines = lines;
        query.before = snippet.id;
      }

      if (this.snippets === null) this.snippets = [];
      this.snippets.push(...snippets);
      query.offset = this.snippets.length;
    },
    getClassForArrow(snippet, approve) {
      return {
        'snippet-arrow-up': approve === true,
        'snippet-arrow-down': approve === false,
        'snippet-arrow-up-pressed': approve === true && snippet.buttonPressed === true,
        'snippet-arrow-down-pressed': approve === false && snippet.buttonPressed === false
      };
    },
    getClassForSnippet(snippet) {
      return {
        'snippet-risk-0': !snippet.license,
        'snippet-risk-1': !!snippet.license
      };
    },
    handleScroll() {
      if (window.innerHeight + Math.ceil(window.scrollY) >= document.documentElement.scrollHeight) {
        this.loadMore();
      }
    },
    async loadMore() {
      if (this.loadingMore) return;
      if (!this.hasMore) return;
      this.loadingMore = true;
      try {
        await this.getSnippets();
      } finally {
        this.loadingMore = false;
      }
    },
    onSearchInput() {
      clearTimeout(this._searchTimer);
      this._searchTimer = setTimeout(() => this.refreshPage(), 300);
    },
    refreshPage() {
      this.hasMore = false;
      this.snippets = null;
      this.params.before = 0;
      this.params.offset = 0;
      this.getSnippets();
    }
  },
  watch: {
    ...genParamWatchers(
      'isClassified',
      'isApproved',
      'isLegal',
      'notLegal',
      'confidence',
      'timeframe',
      'resolution',
      'order',
      'search'
    )
  }
};
</script>

<style>
.snippet-approval a {
  color: rgb(208, 215, 222);
  font-size: 2.5rem;
}
.snippet-arrow-up-pressed a {
  color: green;
}
.snippet-arrow-down-pressed a {
  color: red;
}
.snippet-arrow-up a:hover {
  color: green;
}
.snippet-arrow-down a:hover {
  color: red;
}
.snippet-container {
  margin-bottom: 4rem;
  margin-top: 1rem;
}
.snippet-file {
  background-color: rgb(246, 248, 250);
  border-bottom: 1px solid rgb(208, 215, 222);
  font-size: 13px;
  line-height: 20px;
  padding: 10px;
}
.snippet-file a,
.snippet-likelyness a {
  color: #212529;
  text-decoration: none;
}
.snippet-file a:hover,
.snippet-likelyness a:hover {
  text-decoration: underline;
}
.snippet-file-container {
  border: 1px solid rgb(208, 215, 222);
  border-radius: 6px;
  overflow: hidden;
  padding: 0;
}
.snippet-footer {
  background-color: rgb(246, 248, 250);
  border-top: 1px solid rgb(208, 215, 222);
  font-size: 13px;
  line-height: 20px;
  padding: 10px;
}
.snippet-likelyness {
  display: inline-block;
}

.snippet-risk-0 {
  background-color: #ffffff;
}
.snippet-risk-1 {
  background-color: #fffbdc;
}

.snippet-source {
  background: #fff;
  overflow: auto;
}

.snippet-source td.linenumber,
.snippet-source td.code {
  font-family: monospace;
  padding: 0;
  margin: 0;
  font-size: 12px;
  line-height: 20px;
  color: rgba(27, 31, 35, 0.3);
  border: 0 !important;
}

.snippet-source td.code {
  padding-left: 0.75rem;
  padding-right: 0.75rem;
  color: #24292e;
  margin-left: 0.5em;
  white-space: -moz-pre-wrap;
  white-space: -o-pre-wrap;
  white-space: pre-wrap;
  word-wrap: break-word;
  word-break: break-all;
}

.snippet-source td.linenumber {
  border-right: 1px solid #ddd;
  padding: 0 0.5em;
  margin-right: 0.5em;
  text-align: right;
  width: 1%;
  min-width: 25px;
  color: rgba(27, 31, 35, 0.3);
  user-select: none;
}
</style>
