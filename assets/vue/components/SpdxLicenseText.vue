<template>
  <div class="spdx-license-body">
    <LegalLoading v-if="loading" message="Loading license text..." size="small" />
    <div v-else-if="error" class="alert alert-danger" role="alert">{{ error }}</div>
    <template v-else>
      <div v-if="chips.length" class="spdx-license-chips">
        <span v-for="chip in chips" :key="chip" class="spdx-license-chip">{{ chip }}</span>
      </div>
      <article class="spdx-license-text" data-spdx-text>{{ license.text }}</article>
    </template>
  </div>
</template>

<script>
import LegalLoading from './LegalLoading.vue';
import UserAgent from '@mojojs/user-agent';

// Reviewers reopen the same handful of licenses all day
const cache = new Map();

export default {
  name: 'SpdxLicenseText',
  components: {LegalLoading},
  props: {
    spdxId: {type: String, required: true}
  },
  data() {
    return {
      license: null,
      loading: true,
      error: null,
      ua: new UserAgent({baseURL: window.location.href})
    };
  },
  computed: {
    chips() {
      const about = this.license?.about ?? {};
      const chips = [];
      if (about.osi) chips.push('OSI approved');
      if (about.fsf) chips.push('FSF libre');
      if (about.copyleft && about.copyleft !== 'No') chips.push(`Copyleft: ${about.copyleft}`);
      if (about.source_disclosure && about.source_disclosure !== 'No') {
        chips.push(`Source disclosure: ${about.source_disclosure}`);
      }
      return chips;
    }
  },
  async mounted() {
    const id = this.spdxId;
    try {
      if (!cache.has(id)) {
        const res = await this.ua.get(`/licenses/spdx_meta/${encodeURIComponent(id)}`);
        if (!res.isSuccess) throw new Error(`Server returned ${res.status}`);
        cache.set(id, await res.json());
      }
      this.license = cache.get(id);
    } catch (error) {
      this.error = `Could not load license text: ${error.message}`;
    }
    this.loading = false;
  }
};
</script>

<style>
.spdx-license-body {
  margin: 0 auto;
  max-width: 70ch;
}
.spdx-license-chips {
  display: flex;
  flex-wrap: wrap;
  gap: 0.35rem;
  margin-bottom: 1rem;
}
.spdx-license-chip {
  background: var(--cavil-canvas-subtle);
  border: 1px solid var(--cavil-border);
  border-radius: 999px;
  color: var(--cavil-fg-muted);
  font-size: 12px;
  padding: 1px 8px;
  white-space: nowrap;
}

/* Prose, not the monospace code treatment: nothing here needs column alignment */
.spdx-license-text {
  color: var(--cavil-fg);
  font-size: 15px;
  line-height: 1.7;
  overflow-wrap: break-word;
  white-space: pre-wrap;
}
</style>
