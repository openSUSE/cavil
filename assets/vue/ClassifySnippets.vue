<template>
  <div>
    <div class="row justify-content-center">
      <div v-if="hasClassifierRole === true" class="col-12 alert alert-primary" role="alert">
        These snippets have been pre-processed by our machine learning model to decide if they are legal text or not.
        You can help us improve the model by voting them up or down.
      </div>
    </div>
    <div class="row justify-content-center">
      <div class="col-8">
        <form class="form-inline">
          <div class="form-check mb-2 mr-sm-4">
            <input
              v-model="params.notLegal"
              @change="refreshPage()"
              type="checkbox"
              class="form-check form-check-inline"
              id="snippet-not-legal"
            />
            <label for="snippet-not-legal">Not legal text</label>
          </div>
          <div class="form-check mb-2 mr-sm-4">
            <input
              v-model="params.isLegal"
              @change="refreshPage()"
              type="checkbox"
              class="form-check form-check-inline"
              id="snippet-is-legal"
            />
            <label for="snippet-is-legal">Is legal text</label>
          </div>
          <div class="form-check mb-2 mr-sm-4">
            <input
              v-model="params.isClassified"
              @change="refreshPage()"
              type="checkbox"
              class="form-check form-check-inline"
              id="snippet-is-classified"
            />
            <label for="snippet-is-classified">Classified by AI</label>
          </div>
          <div class="form-check mb-2 mr-sm-4">
            <input
              v-model="params.isApproved"
              @change="refreshPage()"
              type="checkbox"
              class="form-check form-check-inline"
              id="snippet-is-approved"
            />
            <label for="snippet-is-approved">Approved by a human</label>
          </div>
        </form>
      </div>
    </div>
    <div v-if="snippets === null">
      <p><i class="fas fa-sync fa-spin"></i> Loading snippets...</p>
    </div>
    <div v-else-if="snippets.length > 0">
      <div v-for="snippet in snippets" :key="snippet.id" class="row snippet-container">
        <div class="col-11 snippet-file-container">
          <div class="snippet-file">
            <a v-if="snippet.filename !== null" :href="snippet.fileUrl" target="_blank">{{ snippet.filename }}</a>
            <a v-else>Unknown file</a>
            <div v-if="snippet.approved === true" class="float-right">
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
              <div v-if="snippet.license_name !== null">
                <b>{{ snippet.likelyness }}%</b> similarity to <b>{{ snippet.license_name }}</b
                >, estimated risk
                {{ snippet.risk }}
              </div>
              <div v-else>No similarity to any known licenses</div>
            </div>
            <div class="snippet-assessment float-right">
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
        data-toggle="tooltip"
        data-placement="left"
        ><i class="fas fa-angle-up"></i
      ></a>
    </div>
    <div v-else>There are currently no snippets to display</div>
  </div>
</template>

<script>
import UserAgent from '@mojojs/user-agent';

export default {
  name: 'ClassifySnippets',
  data() {
    return {
      params: {isClassified: true, isApproved: false, isLegal: true, notLegal: true, before: 0},
      snippets: null,
      snippetUrl: '/snippets/meta'
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

      for (const snippet of data) {
        snippet.buttonPressed = null;
        snippet.fileUrl = `/reviews/file_view/${snippet.package}/${snippet.filename}`;
        let num = snippet.sline ?? 1;
        const lines = [];
        for (const line of snippet.text.split('\n')) {
          lines.push({num: num++, text: line});
        }
        snippet.lines = lines;
        query.before = snippet.id;
      }

      if (this.snippets === null) this.snippets = [];
      this.snippets.push(...data);
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
      this.snippets = null;
      this.params.before = 0;
      this.getSnippets();
    }
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
  margin-bottom: 3rem;
  margin-top: 5rem;
}
.snippet-file {
  background-color: rgb(246, 248, 250);
  border: 1px solid rgb(208, 215, 222);
  border-radius: 0.25rem 0.25rem 0 0;
  font-size: 13px;
  line-height: 20px;
  padding: 10px;
}
.snippet-file a {
  color: #586069;
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
