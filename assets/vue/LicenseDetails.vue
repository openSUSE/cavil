<template>
  <div id="license-details" class="license-details-page">
    <div v-if="loading" class="license-details-loading">
      <i class="fa-solid fa-rotate fa-spin"></i> Loading license patterns
    </div>
    <div v-else-if="error" class="alert alert-danger" role="alert">{{ error }}</div>
    <template v-else>
      <section class="license-details-header">
        <div class="license-details-title-row">
          <div>
            <div class="license-details-kicker">License patterns</div>
            <h2>{{ details.display_license }}</h2>
          </div>
          <a v-if="canAdmin" class="btn btn-primary" :href="newPatternUrl">
            <i class="fa-solid fa-plus"></i> Add pattern
          </a>
        </div>
        <div class="license-details-meta-row">
          <span class="license-details-stat"
            ><b>{{ patterns.length }}</b> {{ patterns.length === 1 ? 'pattern' : 'patterns' }}</span
          >
          <span class="license-details-stat"
            ><b>{{ formatCount(totalMatches, totalMatchesCapped) }}</b>
            {{ totalMatches === 1 && !totalMatchesCapped ? 'match' : 'matches' }}</span
          >
          <span class="license-details-stat"
            ><b>{{ formatCount(totalPackages, totalPackagesCapped) }}</b>
            {{ totalPackages === 1 && !totalPackagesCapped ? 'package' : 'packages' }}</span
          >
          <span v-for="risk in risks" :key="risk" class="badge" :class="riskClass(risk)">Risk {{ risk }}</span>
        </div>
        <form v-if="canAdmin" class="license-spdx-form" @submit.prevent="saveSpdx">
          <input type="hidden" name="license" :value="details.license" />
          <label class="form-label" for="license-spdx">SPDX</label>
          <div class="license-spdx-control">
            <input v-model="spdx" type="text" id="license-spdx" name="spdx" class="form-control" />
            <button type="submit" class="btn btn-secondary" :disabled="savingSpdx">
              <i v-if="savingSpdx" class="fa-solid fa-rotate fa-spin"></i>
              Save
            </button>
          </div>
        </form>
        <div v-else class="license-details-spdx">
          <span class="license-details-spdx-label">SPDX</span>
          <span v-if="details.spdx_html" v-html="details.spdx_html"></span>
          <span v-else class="text-muted">None</span>
        </div>
      </section>

      <section class="license-details-toolbar" aria-label="Pattern filters">
        <div class="license-filter-search">
          <i class="fa-solid fa-magnifying-glass"></i>
          <input v-model="filter" type="search" class="form-control" placeholder="Filter patterns" />
        </div>
        <select v-model="riskFilter" class="form-select license-filter-risk" aria-label="Risk filter">
          <option value="all">All risks</option>
          <option v-for="risk in risks" :key="risk" :value="String(risk)">Risk {{ risk }}</option>
        </select>
        <select v-model="scopeFilter" class="form-select license-filter-scope" aria-label="Scope filter">
          <option value="all">All scopes</option>
          <option value="global">Global</option>
          <option value="package">Package-specific</option>
        </select>
        <div class="license-details-count">{{ filteredPatterns.length }} shown</div>
      </section>

      <div v-if="filteredPatterns.length === 0" class="license-empty-state">No patterns match the current filters.</div>

      <article
        v-for="pattern in filteredPatterns"
        :key="pattern.id"
        class="license-pattern-card"
        :data-pattern-id="pattern.id"
      >
        <header class="license-pattern-header">
          <div class="license-pattern-heading">
            <span class="license-pattern-id">#{{ pattern.id }}</span>
            <span class="badge" :class="riskClass(pattern.risk)">Risk {{ pattern.risk }}</span>
            <span v-if="pattern.packname" class="license-chip"
              ><i class="fa-solid fa-box"></i> {{ pattern.packname }}</span
            >
            <span v-else class="license-chip"><i class="fa-solid fa-globe"></i> Global</span>
            <span v-for="flag in flagsFor(pattern)" :key="flag" class="license-chip license-chip-flag">{{ flag }}</span>
          </div>
          <div class="license-pattern-actions">
            <a
              class="license-icon-link cavil-icon-action"
              :href="`/search?pattern=${pattern.id}`"
              title="Search matches"
              aria-label="Search matches"
            >
              <i class="fa-solid fa-magnifying-glass"></i>
            </a>
            <button
              v-if="canAdmin"
              type="button"
              class="license-icon-button cavil-icon-action"
              :class="{active: editingId === pattern.id}"
              data-action="edit-pattern-inline"
              title="Edit pattern"
              aria-label="Edit pattern"
              @click="toggleEditor(pattern.id)"
            >
              <i class="fa-solid fa-pen-to-square"></i>
            </button>
          </div>
        </header>

        <div v-if="editingId === pattern.id" class="license-inline-editor">
          <PatternEditor
            :key="`pattern-editor-${pattern.id}-${editorVersion}`"
            :pattern="pattern"
            inline
            :show-match-count="false"
            :show-spdx="false"
            @saved="onPatternSaved"
            @deleted="onPatternDeleted"
            @cancel="editingId = null"
          />
        </div>
        <template v-else>
          <div class="license-pattern-code">
            <table class="pattern">
              <tbody>
                <tr v-for="line in linesFor(pattern)" :key="line.num">
                  <td class="linenumber">{{ line.num }}</td>
                  <td class="code">{{ line.text }}</td>
                </tr>
              </tbody>
            </table>
          </div>
          <button
            v-if="lineCount(pattern) > previewLineLimit"
            type="button"
            class="license-expand-button"
            @click="toggleExpanded(pattern.id)"
          >
            {{ expandedIds.has(pattern.id) ? 'Show less' : `Show ${lineCount(pattern) - previewLineLimit} more lines` }}
          </button>

          <footer class="license-pattern-footer">
            <span
              ><b>{{ formatCount(pattern.matches, pattern.matches_capped) }}</b>
              {{ pattern.matches === 1 && !pattern.matches_capped ? 'match' : 'matches' }} in
              <b>{{ formatCount(pattern.packages, pattern.packages_capped) }}</b>
              {{ pattern.packages === 1 && !pattern.packages_capped ? 'package' : 'packages' }}</span
            >
            <span>
              Created {{ createdFromNow(pattern) }}
              <template v-if="pattern.owner_login">
                by <b>{{ pattern.owner_login }}</b></template
              >
              <template v-if="pattern.contributor_login"
                >, contributed by <b>{{ pattern.contributor_login }}</b></template
              >
            </span>
          </footer>
        </template>
      </article>
    </template>
    <ToastNotifier ref="toaster" />
  </div>
</template>

<script>
import PatternEditor from './components/PatternEditor.vue';
import ToastNotifier from './components/ToastNotifier.vue';
import UserAgent from '@mojojs/user-agent';
import moment from 'moment';

export default {
  name: 'LicenseDetails',
  components: {PatternEditor, ToastNotifier},
  data() {
    return {
      details: null,
      patterns: [],
      loading: true,
      error: null,
      filter: '',
      riskFilter: 'all',
      scopeFilter: 'all',
      spdx: '',
      savingSpdx: false,
      editingId: null,
      editorVersion: 0,
      expandedIds: new Set(),
      previewLineLimit: 12,
      ua: new UserAgent({baseURL: window.location.href})
    };
  },
  computed: {
    canAdmin() {
      return this.details?.can_admin === true;
    },
    detailPathName() {
      return this.licenseName === '' ? '*Pattern without license*' : this.licenseName;
    },
    detailUrl() {
      return `/licenses/meta/${encodeURIComponent(this.detailPathName)}`;
    },
    newPatternUrl() {
      return `/licenses/new_pattern?${new URLSearchParams({'license-name': this.details.license}).toString()}`;
    },
    risks() {
      return [...new Set(this.patterns.map(pattern => Number(pattern.risk)))].sort((a, b) => a - b);
    },
    totalMatches() {
      return this.patterns.reduce((sum, pattern) => sum + Number(pattern.matches || 0), 0);
    },
    totalMatchesCapped() {
      return this.patterns.some(pattern => pattern.matches_capped);
    },
    totalPackages() {
      return this.patterns.reduce((sum, pattern) => sum + Number(pattern.packages || 0), 0);
    },
    totalPackagesCapped() {
      return this.patterns.some(pattern => pattern.packages_capped);
    },
    filteredPatterns() {
      const query = this.filter.trim().toLowerCase();
      return this.patterns.filter(pattern => {
        if (this.riskFilter !== 'all' && String(pattern.risk) !== this.riskFilter) return false;
        if (this.scopeFilter === 'global' && pattern.packname) return false;
        if (this.scopeFilter === 'package' && !pattern.packname) return false;
        if (query === '') return true;
        return [pattern.pattern, pattern.packname, String(pattern.id)].some(value =>
          String(value || '')
            .toLowerCase()
            .includes(query)
        );
      });
    }
  },
  mounted() {
    this.loadDetails();
  },
  methods: {
    async loadDetails() {
      this.error = null;
      this.loading = true;
      try {
        const res = await this.ua.get(this.detailUrl);
        if (!res.isSuccess) throw new Error(`Could not load license details (HTTP ${res.statusCode}).`);
        const details = await res.json();
        this.details = details;
        this.patterns = details.patterns;
        this.spdx = details.spdx ?? '';
      } catch (error) {
        this.error = error.message;
      } finally {
        this.loading = false;
      }
    },
    riskClass(risk) {
      const value = Number(risk);
      if (value >= 1 && value <= 4) return 'text-bg-success';
      if (value === 5) return 'text-bg-warning';
      if (value === 6 || value === 7) return 'text-bg-danger';
      return 'text-bg-dark';
    },
    flagsFor(pattern) {
      const flags = [];
      if (pattern.patent) flags.push('Patent');
      if (pattern.trademark) flags.push('Trademark');
      if (pattern.export_restricted) flags.push('Export restricted');
      return flags;
    },
    formatCount(value, capped = false) {
      return `${Number(value || 0).toLocaleString()}${capped ? '+' : ''}`;
    },
    patternLines(pattern) {
      return String(pattern.pattern ?? '').split('\n');
    },
    lineCount(pattern) {
      return this.patternLines(pattern).length;
    },
    linesFor(pattern) {
      const lines = this.patternLines(pattern);
      const visible = this.expandedIds.has(pattern.id) ? lines : lines.slice(0, this.previewLineLimit);
      return visible.map((text, idx) => ({num: idx + 1, text}));
    },
    createdFromNow(pattern) {
      const value = pattern.created_epoch ? pattern.created_epoch * 1000 : pattern.created;
      return moment(value).fromNow();
    },
    toggleExpanded(id) {
      const next = new Set(this.expandedIds);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      this.expandedIds = next;
    },
    toggleEditor(id) {
      this.editingId = this.editingId === id ? null : id;
      this.editorVersion++;
    },
    async saveSpdx() {
      this.savingSpdx = true;
      try {
        const res = await this.ua.post(this.detailUrl, {form: {license: this.details.license, spdx: this.spdx}});
        const data = await res.json();
        if (!res.isSuccess) throw new Error(data.error || `SPDX update failed with HTTP ${res.statusCode}`);
        this.details.spdx = data.spdx;
        this.details.spdx_html = data.spdx_html;
        this.patterns.forEach(pattern => {
          pattern.spdx = data.spdx;
          pattern.spdx_html = data.spdx_html;
        });
        this.$refs.toaster?.notify(`${data.updated} patterns updated`);
      } catch (error) {
        this.$refs.toaster?.notify(error.message, 'danger', 5000);
      } finally {
        this.savingSpdx = false;
      }
    },
    async onPatternSaved() {
      this.editingId = null;
      await this.loadDetails();
      this.$refs.toaster?.notify('Pattern updated');
    },
    async onPatternDeleted() {
      this.editingId = null;
      await this.loadDetails();
      this.$refs.toaster?.notify('Pattern deleted', 'danger');
    }
  }
};
</script>

<style scoped>
.license-details-page {
  margin-top: 1rem;
}
.license-details-loading,
.license-empty-state {
  border: 1px solid #d0d7de;
  border-radius: 6px;
  color: #57606a;
  padding: 1rem;
  text-align: center;
}
.license-details-header {
  border: 1px solid #d0d7de;
  border-radius: 6px;
  margin-bottom: 1rem;
  overflow: hidden;
}
.license-details-title-row {
  align-items: flex-start;
  background: #f6f8fa;
  border-bottom: 1px solid #d0d7de;
  display: flex;
  gap: 1rem;
  justify-content: space-between;
  padding: 1rem;
}
.license-details-title-row h2 {
  font-size: 24px;
  line-height: 1.25;
  margin: 0;
  overflow-wrap: anywhere;
}
.license-details-kicker {
  color: #57606a;
  font-size: 13px;
  margin-bottom: 0.25rem;
}
.license-details-meta-row,
.license-details-spdx,
.license-spdx-form {
  align-items: center;
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem 0.75rem;
  padding: 0.75rem 1rem;
}
.license-details-stat,
.license-details-spdx-label {
  color: #57606a;
  font-size: 14px;
}
.license-spdx-form {
  border-top: 1px solid #d0d7de;
}
.license-spdx-form .form-label {
  margin: 0;
}
.license-spdx-control {
  display: flex;
  flex: 1;
  gap: 0.5rem;
  min-width: 260px;
}
.license-details-toolbar {
  align-items: center;
  display: grid;
  gap: 0.75rem;
  grid-template-columns: minmax(220px, 1fr) minmax(130px, auto) minmax(170px, auto) auto;
  margin-bottom: 1rem;
}
.license-filter-search {
  position: relative;
}
.license-filter-search i {
  color: #57606a;
  left: 0.75rem;
  position: absolute;
  top: 50%;
  transform: translateY(-50%);
}
.license-filter-search input {
  padding-left: 2.1rem;
}
.license-filter-risk,
.license-filter-scope {
  min-width: 130px;
}
.license-details-count {
  color: #57606a;
  font-size: 14px;
  text-align: right;
  white-space: nowrap;
}
.license-pattern-card {
  border: 1px solid #d0d7de;
  border-radius: 6px;
  margin-bottom: 1rem;
  overflow: hidden;
}
.license-pattern-header,
.license-pattern-footer {
  align-items: center;
  background: #f6f8fa;
  display: flex;
  gap: 0.75rem;
  justify-content: space-between;
  padding: 0.6rem 0.75rem;
}
.license-pattern-header {
  border-bottom: 1px solid #d0d7de;
}
.license-pattern-footer {
  border-top: 1px solid #d0d7de;
  color: #57606a;
  flex-wrap: wrap;
  font-size: 13px;
}
.license-pattern-heading,
.license-pattern-actions {
  align-items: center;
  display: flex;
  flex-wrap: wrap;
  gap: 0.4rem;
}
.license-pattern-id {
  color: #57606a;
  font-family: monospace;
  font-size: 13px;
}
.license-chip {
  align-items: center;
  border: 1px solid #d0d7de;
  border-radius: 999px;
  color: #57606a;
  display: inline-flex;
  font-size: 12px;
  gap: 0.3rem;
  line-height: 1.2;
  padding: 0.2rem 0.45rem;
}
.license-chip-flag {
  background: #fff8c5;
  border-color: #d4a72c;
  color: #7d4e00;
}
.license-pattern-code {
  background: #ffffff;
  overflow: auto;
}
.license-pattern-code table {
  margin: 0;
  width: 100%;
}
.license-pattern-code td.linenumber,
.license-pattern-code td.code {
  border: 0 !important;
  font-family: monospace;
  font-size: 12px;
  line-height: 20px;
  padding-bottom: 0;
  padding-top: 0;
  vertical-align: top;
}
.license-pattern-code td.linenumber {
  border-right: 1px solid #ddd;
  color: rgba(27, 31, 35, 0.3);
  min-width: 25px;
  padding: 0 0.5em;
  margin-right: 0.5em;
  text-align: right;
  user-select: none;
  width: 1%;
}
.license-pattern-code td.code {
  color: #24292f;
  padding-left: 0.75rem;
  padding-right: 0.75rem;
  white-space: pre-wrap;
  word-break: break-word;
}
.license-expand-button {
  background: #ffffff;
  border: 0;
  border-top: 1px solid #d0d7de;
  color: #0969da;
  font-size: 13px;
  padding: 0.45rem 0.75rem;
  text-align: left;
  width: 100%;
}
.license-expand-button:hover {
  background: #f6f8fa;
}
.license-inline-editor {
  border-top: 1px solid #d0d7de;
  padding: 1rem;
}
@media (max-width: 800px) {
  .license-details-toolbar {
    grid-template-columns: 1fr;
  }
  .license-details-count {
    text-align: left;
  }
  .license-spdx-control,
  .license-details-title-row {
    flex-direction: column;
  }
}
</style>
