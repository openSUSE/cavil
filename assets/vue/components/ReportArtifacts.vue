<template>
  <div class="report-artifacts">
    <div v-if="loading" class="report-notes-loading">
      <LegalLoading message="Loading artifacts..." size="small" />
    </div>
    <div v-else-if="loadError" class="report-notes-error" data-artifacts-error>
      <i class="fa-solid fa-triangle-exclamation"></i> {{ loadError }}
      <button type="button" class="report-note-retry" @click="load">Retry</button>
    </div>
    <div v-else-if="isEmpty" class="report-notes-empty" data-artifacts-empty>
      <i class="fa-solid fa-fingerprint"></i>
      <p class="mb-0">Nothing was harvested from this package.</p>
    </div>
    <div v-else>
      <div
        v-for="section in sections"
        :key="section.key"
        class="report-artifact-section"
        :data-artifact-section="section.key"
      >
        <h2 class="report-artifact-heading">
          <a
            :href="`#artifacts-${section.key}`"
            class="report-artifact-label collapsed"
            data-bs-toggle="collapse"
            aria-expanded="false"
            :aria-controls="`artifacts-${section.key}`"
          >
            <i :class="section.icon"></i>
            {{ section.list.total }} {{ section.list.total === 1 ? section.singular : section.plural }}
          </a>
        </h2>
        <div class="collapse" :id="`artifacts-${section.key}`">
          <ul class="report-artifact-list">
            <li v-for="entry in section.list.values" :key="entry[0]" class="report-artifact-item">
              <span class="report-artifact-value">{{ entry[0] }}</span>
              <span class="report-artifact-source">{{ entry[1] }}</span>
            </li>
          </ul>
          <p v-if="section.list.values.length < section.list.total" class="report-artifact-truncated">
            Ordered by occurrences, showing the top {{ section.list.values.length }} of {{ section.list.total }}.
          </p>
        </div>
      </div>
    </div>
  </div>
</template>

<script>
import LegalLoading from './LegalLoading.vue';
import UserAgent from '@mojojs/user-agent';

const EMPTY = {total: 0, values: []};

export default {
  name: 'ReportArtifacts',
  components: {LegalLoading},
  props: {
    pkgId: {type: Number, required: true}
  },
  data() {
    return {
      artifacts: null,
      loading: true,
      loadError: null,
      ua: new UserAgent({baseURL: window.location.href})
    };
  },
  computed: {
    sections() {
      const a = this.artifacts ?? {};
      return [
        {
          key: 'copyrights',
          icon: 'fa-regular fa-copyright',
          singular: 'Copyright notice',
          plural: 'Copyright notices',
          list: a.copyrights ?? EMPTY
        },
        {key: 'emails', icon: 'fa-regular fa-envelope', singular: 'Email', plural: 'Emails', list: a.emails ?? EMPTY},
        {key: 'urls', icon: 'fa-solid fa-link', singular: 'URL', plural: 'URLs', list: a.urls ?? EMPTY}
      ].filter(section => section.list.total > 0);
    },
    isEmpty() {
      return this.sections.length === 0;
    }
  },
  async mounted() {
    await this.load();
  },
  methods: {
    async load() {
      this.loading = true;
      this.loadError = null;
      try {
        const res = await this.ua.get(`/reviews/report_artifacts/${this.pkgId}`);
        if (!res.isSuccess) throw new Error(`Server returned ${res.status}`);
        this.artifacts = await res.json();
      } catch (error) {
        this.loadError = `Could not load artifacts: ${error.message}`;
      }
      this.loading = false;
    }
  }
};
</script>

<style>
/* The pane already spaces itself off the tabs, so the section below them starts flush */
.report-artifacts .report-artifact-section:first-child {
  margin-top: 0;
}
.report-artifact-truncated {
  color: var(--cavil-fg-muted);
  font-size: 12px;
  margin: 0.5rem 0 0;
}
</style>
