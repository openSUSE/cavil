<template>
  <div>
    <div class="row">
      <div v-if="hasClassifierRole === true" class="col-11 alert alert-primary" role="alert">
        These snippets have been pre-processed by our machine learning model to decide if they are legal text or not.
        Legal text is highlighted in yellow. You can help us improve the model by voting the decisions up or down.
      </div>
      <div v-else class="col-11 alert alert-primary" role="alert">
        These snippets have been pre-processed by our machine learning model to decide if they are legal text or not.
        Legal text is highlighted in yellow.
      </div>
    </div>
    <div class="row g-4">
      <div class="col-8">
        <form>
          <div class="row g-4">
            <div class="col-lg-2">
              <div class="form-floating">
                <select v-model="params.confidence" @change="refreshPage()" class="form-control cavil-pkg-confidence">
                  <option value="100">Any</option>
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
            <div class="col-lg-3">
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
            <div class="col">
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
      <div class="col-3">
        <p v-if="total !== null" class="text-end">{{ total }} snippets found</p>
        <p v-else class="text-end"><i class="fas fa-sync fa-spin"></i> Loading snippets</p>
      </div>
    </div>
    <div v-if="snippets !== null && snippets.length > 0">
      <div v-for="snippet in snippets" :key="snippet.id" class="row snippet-container">
        <div class="col-11 snippet-file-container">
          <div class="snippet-file">
            <a v-if="snippet.filename !== null" :href="snippet.fileUrl" target="_blank">{{ snippet.filename }}</a>
            <a v-else>Unknown file</a>
            <span v-if="snippet.files === 2">, and 1 other file</span>
            <span v-else-if="snippet.files > 2">, and {{ snippet.files }} other files</span>
            <div v-if="snippet.approved === true" class="float-end">
              <i class="fas fa-check-circle"></i>
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
              <a @click="approveSnippet(snippet, true)" href="javascript:;"><i class="fas fa-chevron-circle-up"></i></a>
            </div>
            <div :class="getClassForArrow(snippet, false)">
              <a @click="approveSnippet(snippet, false)" href="javascript:;"
                ><i class="fas fa-chevron-circle-down"></i
              ></a>
            </div>
          </div>
        </div>
      </div>
      <a
        id="back-to-top"
        href="#"
        class="btn btn-primary btn-lg back-to-top"
        role="button"
        title="Click to return to the top"
        data-bs-toggle="tooltip"
        data-placement="left"
        ><i class="fas fa-angle-up"></i
      ></a>
    </div>
  </div>
</template>

<script>
import {genParamWatchers, getParams} from './helpers/params.js';
import UserAgent from '@mojojs/user-agent';

export default {
  name: 'ClassifySnippets',
  data() {
    const params = getParams({
      confidence: 100,
      isClassified: true,
      isApproved: false,
      isLegal: true,
      notLegal: true,
      timeframe: 'any'
    });

    return {
      params: {...params, before: 0},
      snippets: null,
      snippetUrl: '/snippets/meta',
      total: null
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
      if (this.total === null || this.total < data.total) this.total = data.total;

      for (const snippet of snippets) {
        snippet.buttonPressed = null;
        snippet.fileUrl = `/reviews/file_view/${snippet.package}/${snippet.filename}`;
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
    loadMore() {
      this.getSnippets();
    },
    refreshPage() {
      this.total = null;
      this.snippets = null;
      this.params.before = 0;
      this.getSnippets();
    }
  },
  watch: {...genParamWatchers('isClassified', 'isApproved', 'isLegal', 'notLegal', 'confidence', 'timeframe')}
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
  border: 1px solid rgb(208, 215, 222);
  border-radius: 0.25rem 0.25rem 0 0;
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
  padding: 0;
}
.snippet-footer {
  background-color: rgb(246, 248, 250);
  border: 1px solid rgb(208, 215, 222);
  border-radius: 0 0.25rem 0.25rem;
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
  border: 1px solid #dfe2e5 !important;
  border-top: 0 !important;
  border-bottom: 0 !important;
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
  padding-left: 0.5em;
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
