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
        <div
          v-if="change.state === 'proposed' && change.action === 'create_pattern'"
          class="col-12 change-file-container"
        >
          <div class="change-header">
            Create Pattern, from <b>{{ change.login }}</b>
            <span v-if="change.package !== null"
              >,
              <a :href="change.package.pkgUrl" target="_blank"
                >for <b>{{ change.package.name }}</b></a
              >
            </span>
            <span v-if="currentUser === change.login" class="float-end">
              <a @click="rejectProposal(change)" href="#"><i class="fas fa-times"></i></a>
            </span>
          </div>
          <div class="change-source">
            <table class="pattern">
              <tbody>
                <tr v-for="line in change.lines" :key="line.num">
                  <td class="linenumber">{{ line.num }}</td>
                  <td class="code">{{ line.text }}</td>
                </tr>
              </tbody>
            </table>
          </div>
          <div class="change-form">
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
          <div class="change-confirmation">Change has been accepted</div>
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
      for (const key of ['patent', 'trademark', 'export_restricted']) {
        change.data[key] = change.data[key] === true ? '1' : '0';
      }
      console.log('Accept proposal', change);
      const ua = new UserAgent({baseURL: window.location.href});
      const form = change.data;
      form['create-pattern'] = 1;
      form.checksum = change.token_hexsum;
      const res = await ua.post(change.createUrl, {form});
      change.state = 'accepted';
      console.log(res);
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
        change.removeUrl = `/licenses/proposed/remove/${change.token_hexsum}`;
        change.createUrl = `/snippet/decision/${change.data.snippet}`;

        if (change.package !== null) change.package.pkgUrl = `/reviews/details/${change.package.id}`;
        if (change.closest !== null) change.closest.licenseUrl = `/licenses/edit_pattern/${change.closest.id}`;

        for (const key of ['patent', 'trademark', 'export_restricted']) {
          change.data[key] = change.data[key] === '1' ? true : false;
        }

        let num = 1;
        const lines = [];
        for (const line of change.data.pattern.split('\n')) {
          lines.push({num: num++, text: line});
        }
        change.lines = lines;

        query.before = change.id;
      }

      if (this.changes === null) this.changes = [];
      this.changes.push(...changes);
      console.log(this.changes);
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
      console.log('Remove proposal', change);
      const ua = new UserAgent({baseURL: window.location.href});
      const res = await ua.post(change.removeUrl);
      change.state = 'rejected';
      console.log(res);
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
</style>
