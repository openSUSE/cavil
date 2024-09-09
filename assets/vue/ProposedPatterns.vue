<template>
  <div>
    <div class="row">
      <div class="col-12 alert alert-primary" role="alert">
        These are license pattern changes proposed by contributors. New patterns are guaranted to match the snippet they
        were created for, and can only use an existing license and risk combination.
      </div>
    </div>
    <div v-if="changes !== null && changes.length > 0">
      <div v-for="change in changes" :key="change.id" class="row change-container">
        <div v-if="change.state === 'proposed'" class="col-12 change-file-container">
          <div class="change-header">
            <span v-if="change.action === 'create_pattern'">
              Create license pattern from
              <a :href="change.editUrl" target="_blank">
                <b v-if="change.data.edited === true">edited snippet</b>
                <b v-else>unedited snippet</b> </a
              >, by <b>{{ change.login }}</b>
              <span v-if="change.package !== null"
                >,
                <a :href="change.package.pkgUrl" target="_blank"
                  >for <b>{{ change.package.name }}</b></a
                >
              </span>
            </span>
            <span v-else-if="change.action === 'create_ignore'">
              Create ignore pattern from <a :href="change.editUrl" target="_blank"> <b>snippet</b></a
              >, by <b>{{ change.login }}</b>
            </span>
            <span v-if="currentUser === change.login" class="float-end">
              <a @click="rejectProposal(change)" href="#"><i class="fas fa-times"></i></a>
            </span>
          </div>
          <div class="change-source">
            <table :class="getClassForCode(change)">
              <tbody>
                <tr v-for="line in change.lines" :key="line.num">
                  <td class="linenumber">{{ line.num }}</td>
                  <td :class="getClassForLine(line)">{{ line.text }}</td>
                </tr>
              </tbody>
            </table>
          </div>
          <div class="change-form">
            <div v-if="change.action === 'create_pattern'">
              <div class="row">
                <div class="col mb-3">
                  <label class="fomr-label" for="license">License</label>
                  <input v-model="change.data.license" type="text" class="form-control" />
                </div>
              </div>
              <div class="row">
                <div class="col-lg-2 mb-3">
                  <div class="form-floating">
                    <select v-model="change.data.risk" class="form-control">
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
                    <input v-model="change.data.patent" type="checkbox" class="form-check-input" />
                    <label class="form-check-label" for="patent">Patent</label>
                  </div>
                  <div class="form-check">
                    <input v-model="change.data.trademark" type="checkbox" class="form-check-input" />
                    <label class="form-check-label" for="trademark">Trademark</label>
                  </div>
                </div>
                <div class="col-lg-2">
                  <div class="form-check">
                    <input v-model="change.data.export_restricted" type="checkbox" class="form-check-input" />
                    <label class="form-check-label" for="export_restricted">Export Restricted</label>
                  </div>
                </div>
              </div>
            </div>
            <div v-else-if="change.action === 'create_ignore'">
              <div class="row">
                <div class="col mb-3">
                  <label class="form-label" for="license">Package</label>
                  <div class="d-flex form-check align-items-center form-check">
                    <input
                      class="form-check-input"
                      id="ignore-one"
                      type="checkbox"
                      name="ignore-for"
                      value="one"
                      v-model="ignoreForPackage"
                    />
                    <input
                      v-model="change.data.from"
                      type="text"
                      class="form-control ms-2"
                      :disabled="!ignoreForPackage"
                    />
                  </div>
                </div>
              </div>
            </div>
            <span v-if="hasAdminRole">
              <button @click="acceptProposal(change)" class="btn btn-success mb-2">Accept</button>
              &nbsp;
              <button @click="rejectProposal(change)" class="btn btn-danger btn-sm mb-2">Reject</button>
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
        <div v-else-if="change.state === 'rejected'" class="col-12">
          <div class="change-confirmation">Proposal has been removed</div>
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
    <div v-else-if="changes === null"><i class="fas fa-sync fa-spin"></i> Loading changes</div>
    <div v-else>There are currently no proposed changes.</div>
  </div>
</template>

<script>
import UserAgent from '@mojojs/user-agent';

export default {
  name: 'RecentChanges',
  data() {
    return {
      ignoreForPackage: true,
      params: {before: 0},
      changes: null,
      changeUrl: '/licenses/proposed/meta',
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
    async acceptProposal(change) {
      change.state = 'updating';

      const ua = new UserAgent({baseURL: window.location.href});
      const form = change.data;
      form.contributor = change.login;
      form.delay = 600;
      if (change.action === 'create_pattern') {
        for (const key of ['patent', 'trademark', 'export_restricted']) {
          change.data[key] = change.data[key] === true ? '1' : '0';
        }
        form['create-pattern'] = 1;
        form.checksum = change.token_hexsum;
      } else if (change.action === 'create_ignore') {
        form.hash = change.token_hexsum;
        if (this.ignoreForPackage === true) {
          form['create-ignore'] = 1;
          form.from = change.data.from;
        } else {
          form['mark-non-license'] = 1;
        }
      }
      await ua.post(change.createUrl, {form});

      change.state = 'accepted';
    },
    async getChanges() {
      const query = this.params;
      const ua = new UserAgent({baseURL: window.location.href});
      const res = await ua.get(this.changeUrl, {query});
      const data = await res.json();

      const changes = data.changes;
      if (this.total === null || this.total < data.total) this.total = data.total;

      for (const change of changes) {
        change.state = 'proposed';
        change.editUrl = `/snippet/edit/${change.data.snippet}`;
        change.removeUrl = `/licenses/proposed/remove/${change.token_hexsum}`;
        change.createUrl = `/snippet/decision/${change.data.snippet}`;

        if (change.package !== null) change.package.pkgUrl = `/reviews/details/${change.package.id}`;
        if (change.closest !== null) change.closest.licenseUrl = `/licenses/edit_pattern/${change.closest.id}`;

        if (change.action === 'create_pattern') {
          for (const key of ['edited', 'patent', 'trademark', 'export_restricted']) {
            change.data[key] = change.data[key] === '1' ? true : false;
          }
        } else if (change.action === 'create_ignore') {
          change.editUrl = `${change.editUrl}?hash=${change.token_hexsum}&from=${change.data.from}`;
        }

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
    getClassForCode(change) {
      return {
        'change-code-ignore': change.action === 'create_ignore',
        'change-code-pattern': change.action === 'create_pattern'
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
    async rejectProposal(change) {
      change.state = 'updating';
      const ua = new UserAgent({baseURL: window.location.href});
      await ua.post(change.removeUrl);
      change.state = 'rejected';
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
.change-code-ignore {
  background: repeating-linear-gradient(-45deg, #ffebe9, #ffebe9 1px, #fff 1px, #fff 5px);
}
</style>
