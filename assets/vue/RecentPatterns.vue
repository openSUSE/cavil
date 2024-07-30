<template>
  <div>
    <div class="row">
      <div class="col-12 alert alert-primary" role="alert">
        These are the most recently added license patterns and some metrics for how well they are performing. The
        metrics are most useful after a full database reindexing.
      </div>
    </div>
    <div v-if="patterns !== null && patterns.length > 0">
      <div v-for="pattern in patterns" :key="pattern.id" class="row recent-pattern-container">
        <div class="col-12 recent-pattern-file-container">
          <div class="recent-pattern-header">
            <b>{{ pattern.license }}</b
            >, risk {{ pattern.risk }}
            <a v-if="hasAdminRole === true" :href="pattern.editUrl" class="float-end"><i class="fas fa-edit"></i></a>
          </div>
          <div class="recent-pattern-source">
            <table class="pattern">
              <tbody>
                <tr v-for="line in pattern.lines" :key="line.num">
                  <td class="linenumber">{{ line.num }}</td>
                  <td class="code">{{ line.text }}</td>
                </tr>
              </tbody>
            </table>
          </div>
          <div class="recent-pattern-footer">
            <a :href="pattern.searchUrl" target="_blank">
              <b>{{ pattern.matches }}</b> matches in <b>{{ pattern.packages }}</b> packages</a
            >
            <span class="float-end">
              <span>Created {{ pattern.created }}</span>
              <span v-if="pattern.owner_login"
                >, by <b>{{ pattern.owner_login }}</b></span
              >
              <span v-if="pattern.contributor_login"
                >, contributed by <b>{{ pattern.owner_login }}</b></span
              >
            </span>
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
    <div v-else><i class="fas fa-sync fa-spin"></i> Loading patterns</div>
  </div>
</template>

<script>
import UserAgent from '@mojojs/user-agent';
import moment from 'moment';

export default {
  name: 'RecentPatterns',
  data() {
    return {
      params: {before: 0},
      patterns: null,
      patternUrl: '/licenses/recent/meta',
      total: null
    };
  },
  mounted() {
    window.addEventListener('scroll', this.handleScroll);
    this.getPatterns();
  },
  beforeDestroy() {
    window.removeEventListener('scroll', this.handleScroll);
  },
  methods: {
    async getPatterns() {
      const query = this.params;
      const ua = new UserAgent({baseURL: window.location.href});
      const res = await ua.get(this.patternUrl, {query});
      const data = await res.json();

      const patterns = data.patterns;
      if (this.total === null || this.total < data.total) this.total = data.total;

      for (const pattern of patterns) {
        pattern.editUrl = `/licenses/edit_pattern/${pattern.id}`;
        pattern.searchUrl = `/search?pattern=${pattern.id}`;
        let num = 1;
        const lines = [];
        for (const line of pattern.pattern.split('\n')) {
          lines.push({num: num++, text: line});
        }
        pattern.lines = lines;
        pattern.created = moment(pattern.created_epoch * 1000).fromNow();
        query.before = pattern.id;
      }

      if (this.patterns === null) this.patterns = [];
      this.patterns.push(...patterns);
    },
    handleScroll() {
      if (window.innerHeight + Math.ceil(window.scrollY) >= document.documentElement.scrollHeight) {
        this.loadMore();
      }
    },
    loadMore() {
      this.getPatterns();
    }
  }
};
</script>

<style scoped>
.recent-pattern-container {
  margin-bottom: 4rem;
  margin-top: 1rem;
}
.recent-pattern-header {
  background-color: rgb(246, 248, 250);
  border: 1px solid rgb(208, 215, 222);
  border-radius: 0.25rem 0.25rem 0 0;
  font-size: 13px;
  line-height: 20px;
  padding: 10px;
}
.recent-pattern-header a,
.recent-pattern-footer a,
.recent-pattern-file a {
  color: #212529;
  text-decoration: none;
}
.recent-pattern-footer a:hover,
.recent-pattern-file a:hover {
  text-decoration: underline;
}
.recent-pattern-file-container {
  padding: 0;
}
.recent-pattern-footer {
  background-color: rgb(246, 248, 250);
  border: 1px solid rgb(208, 215, 222);
  border-radius: 0 0.25rem 0.25rem;
  font-size: 13px;
  line-height: 20px;
  padding: 10px;
}
.recent-pattern-source {
  border: 1px solid #dfe2e5 !important;
  border-top: 0 !important;
  border-bottom: 0 !important;
}
.recent-pattern-source td.linenumber,
.recent-pattern-source td.code {
  font-family: monospace;
  padding: 0;
  margin: 0;
  font-size: 12px;
  line-height: 20px;
  color: rgba(27, 31, 35, 0.3);
  border: 0 !important;
}
.recent-pattern-source td.code {
  padding-left: 0.5em;
  color: #24292e;
  margin-left: 0.5em;
  white-space: -moz-pre-wrap;
  white-space: -o-pre-wrap;
  white-space: pre-wrap;
  word-wrap: break-word;
  word-break: break-all;
}
.recent-pattern-source td.linenumber {
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
