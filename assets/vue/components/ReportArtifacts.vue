<template>
  <div class="report-artifacts">
    <div v-if="loading" class="report-notes-loading">
      <LegalLoading message="Loading artifacts..." size="small" />
    </div>
    <div v-else-if="loadError" class="report-notes-error" data-artifacts-error>
      <i class="fa-solid fa-triangle-exclamation"></i> {{ loadError }}
      <button type="button" class="report-note-retry" @click="load">Retry</button>
    </div>
    <div v-else-if="sections.length === 0" class="report-notes-empty" data-artifacts-empty>
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
          <span class="report-artifact-label report-artifact-label-static">
            <i :class="section.icon"></i>
            {{ section.total }} {{ section.total === 1 ? section.singular : section.plural }}
          </span>
        </h2>
        <ul class="report-artifact-list">
          <li v-for="entry in section.shown" :key="entry[0]" class="report-artifact-item">
            <span class="report-artifact-value">{{ entry[0] }}</span>
            <span class="report-artifact-source">{{ section.unit(entry[1]) }}</span>
          </li>
          <li v-if="section.canExpand" class="report-artifact-more">
            <button type="button" :data-artifact-more="section.key" @click="toggle(section)">
              <i :class="expanded[section.key] ? 'fa-solid fa-chevron-up' : 'fa-solid fa-chevron-down'"></i>
              {{
                expanded[section.key] ? 'Show top ' + PREVIEW : 'Show ' + (section.values.length - PREVIEW) + ' more'
              }}
            </button>
          </li>
        </ul>
      </div>
    </div>
  </div>
</template>

<script>
import LegalLoading from './LegalLoading.vue';
import UserAgent from '@mojojs/user-agent';

// Reviewers read these top down looking for what occurs most, so the head of each list is what the tab
// opens on; the tail is a click away rather than a scroll past three lists of several hundred rows
const PREVIEW = 10;

const EMPTY = {total: 0, values: []};
// Copyright notices are counted in the files they cover, the other two in how often they occur. Both
// numbers are spelled out: a bare count next to a labelled one reads as the same thing measured twice.
const OCCURRENCES = count => `${count} ${count === 1 ? 'occurrence' : 'occurrences'}`;
const FILES = count => `${count} ${count === 1 ? 'file' : 'files'}`;

export default {
  name: 'ReportArtifacts',
  components: {LegalLoading},
  props: {
    pkgId: {type: Number, required: true}
  },
  data() {
    return {
      PREVIEW,
      artifacts: null,
      expanded: {},
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

          unit: FILES,
          list: a.copyrights ?? EMPTY
        },
        {
          key: 'emails',
          icon: 'fa-regular fa-envelope',
          singular: 'Email',
          plural: 'Emails',
          unit: OCCURRENCES,
          list: a.emails ?? EMPTY
        },
        {
          key: 'urls',
          icon: 'fa-solid fa-link',
          singular: 'URL',
          plural: 'URLs',
          unit: OCCURRENCES,
          list: a.urls ?? EMPTY
        }
      ]
        .filter(section => section.list.total > 0)
        .map(section => {
          const values = section.list.values;
          const canExpand = values.length > PREVIEW;
          return {
            ...section,
            values,
            canExpand,
            total: section.list.total,
            shown: canExpand && !this.expanded[section.key] ? values.slice(0, PREVIEW) : values
          };
        });
    }
  },
  async mounted() {
    await this.load();
  },
  methods: {
    toggle(section) {
      this.expanded[section.key] = !this.expanded[section.key];
    },
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
/* Same left wash the legal-document and unresolved-match rows use, in neutral rather than a hue that
   would read as a verdict. Dark gets an inset rule instead: a wash over near-black is only grey haze. */
.report-artifacts .report-artifact-item,
.report-artifacts .report-artifact-more {
  background: linear-gradient(90deg, rgba(var(--cavil-neutral-rgb), 0.08), var(--cavil-canvas) 2.5rem);
}
.report-artifacts .report-artifact-item:hover,
.report-artifacts .report-artifact-more button:hover {
  background: linear-gradient(90deg, rgba(var(--cavil-neutral-rgb), 0.12), var(--cavil-canvas-subtle) 2.5rem);
}
[data-bs-theme='dark'] .report-artifacts .report-artifact-item,
[data-bs-theme='dark'] .report-artifacts .report-artifact-more {
  background: var(--cavil-canvas);
  box-shadow: inset 2px 0 0 var(--cavil-border-strong);
}
[data-bs-theme='dark'] .report-artifacts .report-artifact-item:hover,
[data-bs-theme='dark'] .report-artifacts .report-artifact-more button:hover {
  background: var(--cavil-canvas-subtle);
}

/* The last row of the list rather than a control floating under it */
.report-artifact-more {
  border-top: 1px solid var(--cavil-border-muted);
}

.report-artifact-more button {
  align-items: center;
  background: transparent;
  border: 0;
  color: var(--cavil-fg-muted);
  cursor: pointer;
  display: flex;
  font-size: 13px;
  font-weight: 600;
  gap: 0.45rem;
  justify-content: center;
  padding: 0.6rem 1rem;
  width: 100%;
}
.report-artifact-more button:hover {
  color: var(--cavil-accent);
}
</style>
