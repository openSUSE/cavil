<template>
  <div>
    <div class="row mt-3">
      <div class="col-12 alert alert-primary" role="alert">
        These are snippets with possibly missing licenses or license combinations that have been flagged by contributors
        for risk assessment.
      </div>
    </div>
    <div v-if="changes !== null && changes.length > 0">
      <div v-for="change in changes" :key="change.id" class="row change-container">
        <div v-if="change.state === 'proposed'" class="col-12 change-file-container">
          <div class="change-header">
            <span v-if="change.action === 'missing_license'">
              Missing license reported by <b>{{ change.login }}</b>
              <span v-if="change.package !== null"
                >,
                <a :href="change.package.pkgUrl" target="_blank"
                  >for <b>{{ change.package.name }}</b></a
                >
              </span>
            </span>
            <span v-if="currentUser === change.login" class="float-end">
              <a @click="dismissProposal(change)" href="#"><i class="fas fa-times"></i></a>
            </span>
          </div>
          <div class="change-source">
            <table>
              <tbody>
                <tr v-for="line in change.lines" :key="line.num">
                  <td class="linenumber">{{ line.num }}</td>
                  <td :class="getClassForLine(line)">{{ line.text }}</td>
                </tr>
              </tbody>
            </table>
          </div>
          <div class="change-form">
            <span v-if="hasAdminRole">
              <a class="btn btn-primary mb-2" :href="change.editUrl" target="_blank" role="button">Edit Pattern</a>
              &nbsp;
              <button @click="dismissProposal(change)" class="btn btn-danger btn-sm mb-2">Dismiss</button>
            </span>
          </div>
          <div class="change-footer">
            <div v-if="change.closest !== null">
              <a :href="change.closest.licenseUrl" target="_blank">
                <b>{{ change.closest.similarity }}%</b> similarity to
                <b>{{ change.closest.license_name === '' ? 'Keyword Pattern' : change.closest.license_name }}</b
                >, estimated risk
                {{ change.closest.risk }}
              </a>
            </div>
            <div v-else>No similarity to any known licenses</div>
          </div>
        </div>
        <div v-else-if="change.state === 'updating'" class="col-12">
          <div class="change-confirmation"><i class="fas fa-sync fa-spin"></i> Updating proposal</div>
        </div>
        <div v-else-if="change.state === 'accepted'" class="col-12">
          <div class="change-confirmation">
            Change has been accepted, reindexing related packages in 10 minutes if necessary
          </div>
        </div>
        <div v-else-if="change.state === 'dismissed'" class="col-12">
          <div class="change-confirmation">Proposal has been dismissed</div>
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
    <div v-else-if="changes === null"><i class="fas fa-sync fa-spin"></i> Loading missing licenses</div>
    <div v-else>There are currently no missing licenses.</div>
  </div>
</template>

<script>
import UserAgent from '@mojojs/user-agent';

export default {
  name: 'MissingLicenses',
  data() {
    return {
      ignoreForPackage: true,
      params: {before: 0},
      changes: null,
      changeUrl: '/licenses/proposed/meta?action=missing_license',
      total: null
    };
  },
  mounted() {
    window.addEventListener('scroll', this.handleScroll);
    this.getChanges();
  },
  beforeDestroy() {
    window.removeEventListener('scroll', this.handleScroll);
  },
  methods: {
    async getChanges() {
      const query = this.params;
      const ua = new UserAgent({baseURL: window.location.href});
      const res = await ua.get(this.changeUrl, {query});
      const data = await res.json();

      const changes = data.changes;
      if (this.total === null || this.total < data.total) this.total = data.total;

      for (const change of changes) {
        change.state = 'proposed';
        change.editUrl = `/snippet/edit/${change.data.snippet}?hash=${change.token_hexsum}&from=${change.data.from}`;
        change.removeUrl = `/licenses/proposed/remove/${change.token_hexsum}`;

        if (change.package !== null) change.package.pkgUrl = `/reviews/details/${change.package.id}`;
        if (change.closest !== null) change.closest.licenseUrl = `/licenses/edit_pattern/${change.closest.id}`;

        const highlightedKeywords = change.data.highlighted_keywords ?? [];
        const highlightedLicenses = change.data.highlighted_licenses ?? [];
        let num = 0;
        const lines = [];
        for (const text of change.data.pattern.split('\n')) {
          const isKeyword = highlightedKeywords.includes(num.toString());
          const isLicense = highlightedLicenses.includes(num.toString());
          const highlighted = isLicense ? 'license' : isKeyword ? 'keyword' : null;
          lines.push({num: ++num, text, highlighted});
        }
        change.lines = lines;

        query.before = change.id;
      }

      if (this.changes === null) this.changes = [];
      this.changes.push(...changes);
    },
    getClassForLine(line) {
      return {
        'change-keyword-line code': line.highlighted === 'keyword',
        'change-license-line code': line.highlighted === 'license',
        code: line.highlighted === null
      };
    },
    handleScroll() {
      if (window.innerHeight + Math.ceil(window.scrollY) >= document.documentElement.scrollHeight) {
        this.loadMore();
      }
    },
    loadMore() {
      this.getChanges();
    },
    async dismissProposal(change) {
      change.state = 'updating';
      const ua = new UserAgent({baseURL: window.location.href});
      await ua.post(change.removeUrl);
      change.state = 'dismissed';
    }
  }
};
</script>

<style scoped>
.change-confirmation {
  background-color: rgb(246, 248, 250);
  border: 1px solid rgb(208, 215, 222);
  border-radius: 0.25rem;
  font-size: 13px;
  line-height: 20px;
  padding: 10px;
}
.change-container {
  margin-bottom: 4rem;
  margin-top: 1rem;
}
.change-header {
  background-color: rgb(246, 248, 250);
  border: 1px solid rgb(208, 215, 222);
  border-radius: 0.25rem 0.25rem 0 0;
  font-size: 13px;
  line-height: 20px;
  padding: 10px;
}
.change-header a,
.change-file a,
.change-footer a {
  color: #212529;
  text-decoration: none;
}
.change-header a:hover b,
.change-file a:hover,
.change-footer a:hover {
  text-decoration: underline;
}
.change-file-container {
  padding: 0;
}
.change-form {
  background-color: rgb(246, 248, 250);
  border: 1px solid rgb(208, 215, 222);
  border-bottom: 0;
  padding: 10px;
}
.change-footer {
  background-color: rgb(246, 248, 250);
  border: 1px solid rgb(208, 215, 222);
  border-radius: 0 0.25rem 0.25rem;
  font-size: 13px;
  line-height: 20px;
  padding: 10px;
}
.change-source {
  border: 1px solid #dfe2e5 !important;
  border-top: 0 !important;
  border-bottom: 0 !important;
}
.change-source td.linenumber,
.change-source td.code {
  font-family: monospace;
  padding: 0;
  margin: 0;
  font-size: 12px;
  line-height: 20px;
  color: rgba(27, 31, 35, 0.3);
  border: 0 !important;
}
.change-source td.code {
  padding-left: 0.5em;
  color: #24292e;
  margin-left: 0.5em;
  white-space: -moz-pre-wrap;
  white-space: -o-pre-wrap;
  white-space: pre-wrap;
  word-wrap: break-word;
  word-break: break-all;
}
.change-source td.linenumber {
  border-right: 1px solid #ddd;
  padding: 0 0.5em;
  margin-right: 0.5em;
  text-align: right;
  width: 1%;
  min-width: 25px;
  color: rgba(27, 31, 35, 0.3);
  user-select: none;
}
.change-license-line {
  background-color: #ebffe9;
}
.change-keyword-line {
  background-color: #ffebe9;
}
</style>
