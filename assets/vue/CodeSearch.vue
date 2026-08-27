<template>
  <div class="cavil-list-page mt-3 code-search">
    <section class="code-search-query" aria-labelledby="code-search-query-title" :aria-busy="loading">
      <header class="code-search-query-header">
        <h2 id="code-search-query-title">Search reviewed source</h2>
      </header>
      <form class="code-search-query-form" @submit.prevent="search">
        <label id="code-search-snippet-label" for="code-search-snippet">Code snippet</label>
        <PatternCodeMirror
          v-model="snippet"
          :line-numbers="false"
          aria-label="Code snippet"
          content-id="code-search-snippet"
          class="code-search-editor"
        />
        <div class="code-search-query-actions">
          <button type="submit" class="btn btn-primary code-search-submit" :disabled="loading || !canSearch">
            <i :class="loading ? 'fa-solid fa-spinner fa-spin' : 'fa-solid fa-magnifying-glass'" aria-hidden="true"></i>
            {{ loading ? 'Searching' : 'Search code' }}
          </button>
        </div>
      </form>
    </section>

    <section v-if="searched && !loading" class="code-search-results" aria-live="polite">
      <div v-if="matches.length" class="code-search-results-panel">
        <header class="code-search-results-header">
          <div class="cavil-list-title">
            <strong>{{ total.toLocaleString() }}</strong>
            <span>{{ total === 1 ? 'matching source' : 'matching sources' }}</span>
          </div>
        </header>

        <div class="code-search-results-list">
          <article v-for="match in matches" :key="match.hash" class="code-search-result">
            <header class="code-search-result-header">
              <div class="code-search-result-identity">
                <a :href="fileUrl(primary(match))" class="code-search-result-path" target="_blank" rel="noopener">
                  <strong>{{ primary(match).name }}</strong>
                  <span class="code-search-path-separator">/</span>
                  <span>{{ primary(match).filename }}</span>
                </a>
              </div>
              <div class="code-search-result-tags">
                <span
                  v-for="license in match.licenses"
                  :key="license"
                  class="cavil-meta-badge cavil-meta-badge-muted"
                >
                  {{ license }}
                </span>
                <span v-if="match.risk != null" :class="['cavil-meta-badge', riskClass(match.risk)]"
                  >Risk {{ match.risk }}</span
                >
                <span
                  :class="[
                    'cavil-meta-badge',
                    'code-search-match-kind',
                    match.exact ? 'cavil-meta-badge-success' : 'cavil-meta-badge-warning'
                  ]"
                >
                  {{ match.exact ? 'Exact match' : 'Modified match' }}
                </span>
              </div>
              <div class="code-search-result-measurements">
                <div class="code-search-match-evidence">
                  <span class="code-search-match-count">
                    {{ match.aligned }} of {{ match.total }} fingerprints aligned
                  </span>
                  <span
                    class="code-search-match-map"
                    role="img"
                    :aria-label="`${match.aligned} of ${match.total} fingerprints aligned`"
                  >
                    <span
                      v-for="block in 10"
                      :key="block"
                      class="code-search-match-cell"
                      :class="{'is-on': block <= matchBlocks(match)}"
                    ></span>
                  </span>
                </div>
                <div class="code-search-coverage">
                  <span class="code-search-coverage-label">File coverage</span>
                  <span class="code-search-coverage-value">{{ percent(match.containment_of) }}</span>
                </div>
              </div>
            </header>

            <div v-if="match.excerpt.length" class="source">
              <table>
                <tbody>
                  <tr v-for="line in match.excerpt" :key="line.number" :class="{'cavil-cs-match': line.matched}">
                    <td class="linenumber">{{ line.number }}</td>
                    <td class="code">{{ line.text }}</td>
                  </tr>
                </tbody>
              </table>
            </div>

            <details v-if="match.files.length > 1" class="code-search-result-locations">
              <summary>
                <i class="fa-solid fa-chevron-right" aria-hidden="true"></i>
                {{ match.files.length - 1 }} other {{ match.files.length === 2 ? 'location' : 'locations' }}
              </summary>
              <ul>
                <li v-for="file in match.files.slice(1)" :key="file.package + file.filename">
                  <a :href="fileUrl(file)" target="_blank" rel="noopener">
                    <span class="code-search-location-package">{{ file.name }}</span>
                    <span class="code-search-location-separator" aria-hidden="true">/</span>
                    <span class="code-search-location-path">{{ file.filename }}</span>
                  </a>
                </li>
              </ul>
            </details>
          </article>
        </div>

        <div v-if="loadingMore" class="code-search-loading-more">
          <i class="fa-solid fa-spinner fa-spin" aria-hidden="true"></i>
          Loading more matches
        </div>
      </div>

      <div v-else-if="tooShort" class="code-search-empty">
        <span class="code-search-empty-icon" aria-hidden="true"><i class="fa-regular fa-file-code"></i></span>
        <strong>This snippet is too short or too repetitive to locate reliably.</strong>
        <span
          >Paste a longer, more distinctive sample; short or highly repetitive code lacks the unique detail needed to
          find it.</span
        >
      </div>

      <div v-else class="code-search-empty">
        <span class="code-search-empty-icon" aria-hidden="true"><i class="fa-regular fa-file-code"></i></span>
        <strong>No matching open source code found.</strong>
        <span>The submitted fragment did not overlap with indexed source files.</span>
      </div>
    </section>
  </div>
</template>

<script>
import PatternCodeMirror from './components/PatternCodeMirror.vue';
import UserAgent from '@mojojs/user-agent';

const PAGE = 10;

export default {
  name: 'CodeSearch',
  components: {PatternCodeMirror},
  data() {
    return {
      snippet: '',
      matches: [],
      total: 0,
      tooShort: false,
      loading: false,
      loadingMore: false,
      searched: false
    };
  },
  computed: {
    canSearch() {
      return this.snippet.trim().length > 0;
    }
  },
  mounted() {
    window.addEventListener('scroll', this.onScroll);
  },
  beforeUnmount() {
    window.removeEventListener('scroll', this.onScroll);
  },
  methods: {
    async search() {
      if (!this.canSearch) return;
      this.loading = true;
      this.matches = [];
      await this.loadPage();
      this.searched = true;
      this.loading = false;
    },
    async loadPage() {
      const ua = new UserAgent({baseURL: window.location.href});
      const form = {snippet: this.snippet, limit: PAGE, offset: this.matches.length};
      const data = await (await ua.post('/code-search/query', {form})).json();
      this.matches.push(...(data.matches ?? []));
      this.total = data.total ?? 0;
      this.tooShort = data.too_short ?? false;
    },
    async onScroll() {
      if (this.loading || this.loadingMore || this.matches.length >= this.total) return;
      if (window.innerHeight + window.scrollY < document.body.offsetHeight - 300) return;
      this.loadingMore = true;
      await this.loadPage();
      this.loadingMore = false;
    },
    primary(match) {
      return match.files[0] ?? {};
    },
    fileUrl(file) {
      return `/reviews/file_view/${file.package}/${file.filename}`;
    },
    percent(value) {
      if (value > 0 && value < 0.01) return '<1%';
      return `${Math.round((value ?? 0) * 100)}%`;
    },
    matchBlocks(match) {
      if (!match.total || match.aligned <= 0) return 0;
      if (match.aligned >= match.total) return 10;
      return Math.max(1, Math.floor((match.aligned / match.total) * 10));
    },
    riskClass(risk) {
      const value = Number(risk);
      if (value >= 1 && value <= 4) return 'cavil-meta-badge-success';
      if (value === 5) return 'cavil-meta-badge-warning';
      if (value === 6 || value === 7) return 'cavil-meta-badge-danger';
      return 'cavil-risk-unknown-badge';
    }
  }
};
</script>

<style scoped>
.code-search {
  color: var(--cavil-fg-emphasis);
  font-size: 0.875rem;
  line-height: 1.5;
  margin-bottom: 4rem;
  margin-inline: auto;
  max-width: 1120px;
}
.code-search-query,
.code-search-results-panel,
.code-search-empty {
  background: var(--cavil-canvas);
  border: 1px solid var(--cavil-border);
  border-radius: 6px;
  overflow: hidden;
}
.code-search-query-header {
  background: var(--cavil-canvas-subtle);
  border-bottom: 1px solid var(--cavil-border-muted);
  padding: 0.6rem 0.75rem;
}
.code-search-query-header h2 {
  font-size: 0.9375rem;
  font-weight: 600;
  line-height: 1.3;
  margin: 0;
}
.code-search-query-form {
  padding: 0.75rem;
}
.code-search-query-form > label {
  color: var(--cavil-fg-emphasis);
  display: block;
  font-size: 0.8125rem;
  font-weight: 600;
  margin-bottom: 0.4rem;
}
.code-search-editor :deep(.pattern-codemirror-host) {
  border-color: var(--cavil-border-strong);
  border-radius: 6px;
}
.code-search-editor :deep(.cm-content) {
  min-height: 10rem;
  padding: 0.65rem 0;
}
.code-search-editor :deep(.cm-focused) {
  box-shadow:
    inset 0 0 0 1px var(--cavil-accent),
    0 0 0 3px rgba(var(--cavil-accent-rgb), 0.15);
}
.code-search-query-actions {
  align-items: center;
  display: flex;
  justify-content: flex-end;
  margin-top: 0.75rem;
}
.code-search-submit {
  align-items: center;
  display: inline-flex;
  flex: 0 0 auto;
  font-size: 0.8125rem;
  font-weight: 600;
  gap: 0.4rem;
  min-height: 2rem;
  padding: 0.35rem 0.75rem;
}
.code-search-results {
  margin-top: 1.5rem;
}
.code-search-results-header {
  align-items: center;
  background: var(--cavil-canvas-subtle);
  border-bottom: 1px solid var(--cavil-border-muted);
  display: flex;
  gap: 1rem;
  justify-content: space-between;
  padding: 0.55rem 0.75rem;
}
.cavil-list-title {
  align-items: center;
  display: inline-flex;
  gap: 0.35rem;
}
.cavil-list-title strong {
  font-weight: 600;
}
.code-search-result {
  background: var(--cavil-canvas);
  border-bottom: 1px solid var(--cavil-border);
}
.code-search-result:last-child {
  border-bottom: 0;
}
.code-search-result-header {
  background: var(--cavil-canvas-subtle);
  border-bottom: 1px solid var(--cavil-border-muted);
  padding: 0.7rem 0.8rem;
}
.code-search-result-identity {
  min-width: 0;
}
.code-search-result-path {
  align-items: baseline;
  color: var(--cavil-accent);
  display: flex;
  gap: 0.3rem;
  line-height: 1.35;
  min-width: 0;
  text-decoration: none;
}
.code-search-result-path:hover,
.code-search-result-path:focus {
  text-decoration: underline;
}
.code-search-result-path strong {
  flex: 0 0 auto;
  font-weight: 600;
}
.code-search-result-path span:last-child {
  min-width: 0;
  overflow-wrap: anywhere;
}
.code-search-path-separator {
  color: var(--cavil-fg-disabled);
}
.code-search-result-tags {
  align-items: center;
  display: flex;
  flex-wrap: wrap;
  gap: 0.35rem;
  margin-top: 0.45rem;
}
.code-search-result-measurements {
  align-items: center;
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem 1rem;
  justify-content: space-between;
  margin-top: 0.45rem;
}
.code-search-coverage {
  align-items: baseline;
  display: grid;
  gap: 0 0.3rem;
  grid-template-columns: auto auto;
  white-space: nowrap;
}
.code-search-match-evidence {
  align-items: center;
  display: flex;
  flex-wrap: wrap;
  gap: 0.35rem 0.65rem;
  justify-content: flex-start;
}
.code-search-match-kind {
  text-transform: none;
}
.code-search-match-count {
  color: var(--cavil-fg-muted);
  font-size: 0.75rem;
  white-space: nowrap;
}
.code-search-match-map {
  display: flex;
  flex-wrap: wrap;
  gap: 2px;
  justify-content: flex-start;
  justify-self: start;
  max-width: 24rem;
}
.code-search-match-cell {
  background: var(--cavil-border);
  border-radius: 1px;
  flex: 0 0 8px;
  height: 8px;
  width: 8px;
}
.code-search-match-cell.is-on {
  background: var(--cavil-success);
}
.code-search-coverage-value {
  color: var(--cavil-fg-emphasis);
  font-size: 0.8125rem;
  font-weight: 600;
}
.code-search-coverage-label {
  color: var(--cavil-fg-muted);
  font-size: 0.6875rem;
}
.code-search-result .source {
  background: var(--cavil-canvas);
  border: 0 !important;
  border-radius: 0 !important;
  margin: 0;
  overflow-x: auto;
}
.code-search-result .source table {
  width: 100%;
}
.code-search-result .source td.code {
  white-space: pre;
  word-break: normal;
}
.code-search-result-locations {
  background: var(--cavil-canvas-subtle);
  border-top: 1px solid var(--cavil-border-muted);
  color: var(--cavil-fg-muted);
  font-size: 0.75rem;
}
.code-search-result-locations summary {
  align-items: center;
  cursor: pointer;
  display: flex;
  gap: 0.4rem;
  list-style: none;
  padding: 0.5rem 0.8rem;
  user-select: none;
}
.code-search-result-locations summary::-webkit-details-marker {
  display: none;
}
.code-search-result-locations summary:hover {
  color: var(--cavil-fg-emphasis);
}
.code-search-result-locations summary i {
  color: var(--cavil-fg-subtle);
  font-size: 0.625rem;
  transition: transform 0.15s ease;
}
.code-search-result-locations[open] summary i {
  transform: rotate(90deg);
}
.code-search-result-locations ul {
  display: grid;
  gap: 0.2rem;
  list-style: none;
  margin: 0;
  padding: 0 0.8rem 0.6rem 1.8rem;
}
.code-search-result-locations li {
  min-width: 0;
}
.code-search-result-locations a {
  color: var(--cavil-fg-muted);
  display: flex;
  gap: 0.3rem;
  line-height: 1.4;
  min-width: 0;
  overflow-wrap: anywhere;
  text-decoration: none;
}
.code-search-result-locations a:hover,
.code-search-result-locations a:focus {
  color: var(--cavil-accent-strong);
  text-decoration: underline;
}
.code-search-location-package {
  flex: 0 0 auto;
  font-weight: 600;
}
.code-search-location-separator {
  color: var(--cavil-fg-disabled);
}
.code-search-location-path {
  min-width: 0;
}
.code-search-loading-more {
  border-top: 1px solid var(--cavil-border-muted);
  color: var(--cavil-fg-muted);
  font-size: 0.8125rem;
  padding: 0.7rem;
  text-align: center;
}
.code-search-loading-more i {
  margin-right: 0.35rem;
}
.code-search-empty {
  align-items: center;
  color: var(--cavil-fg-muted);
  display: flex;
  flex-direction: column;
  padding: 2.75rem 1rem;
  text-align: center;
}
.code-search-empty-icon {
  align-items: center;
  background: var(--cavil-accent-bg);
  border: 1px solid var(--cavil-accent-border);
  border-radius: 6px;
  color: var(--cavil-accent);
  display: inline-flex;
  flex: 0 0 auto;
  height: 2.5rem;
  justify-content: center;
  margin-bottom: 0.8rem;
  width: 2.5rem;
}
.code-search-empty strong {
  color: var(--cavil-fg-emphasis);
  font-size: 0.9375rem;
  margin-bottom: 0.2rem;
}
.code-search-empty > span:last-child {
  font-size: 0.8125rem;
}
@media (max-width: 700px) {
  .code-search-query-actions {
    align-items: stretch;
    flex-direction: column;
  }
  .code-search-submit {
    justify-content: center;
    width: 100%;
  }
  .code-search-match-map {
    justify-content: flex-start;
    justify-self: start;
    max-width: 100%;
  }
}
</style>
