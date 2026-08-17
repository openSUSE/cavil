<template>
  <div class="report-documents">
    <span v-if="current.state === 'unavailable'" class="report-documents-note">not available</span>
    <template v-else-if="current.state === 'ready'">
      <div v-for="doc in current.documents" :key="doc.key" class="report-documents-row">
        <a class="report-documents-control report-documents-ready" :href="doc.url" :download="doc.name">
          <i class="fa-solid fa-file-arrow-down" aria-hidden="true"></i>
          <span>{{ doc.name }}</span>
        </a>
        <span v-if="doc.size" class="report-documents-size">{{ doc.size }}</span>
      </div>
    </template>
    <div v-else class="report-documents-row">
      <!-- The same control throughout: asking for the documents and waiting for them are one affordance,
           so only the glyph and the label change under the cursor -->
      <button
        type="button"
        class="report-documents-control"
        :disabled="building || busy"
        :aria-busy="building"
        @click="generate"
      >
        <i :class="building ? 'fa-solid fa-rotate fa-spin' : 'fa-solid fa-file-arrow-down'" aria-hidden="true"></i>
        <span>{{ label }}</span>
      </button>
      <span v-if="current.state === 'failed'" class="report-documents-note">last attempt failed</span>
    </div>
  </div>
</template>

<script>
import UserAgent from '@mojojs/user-agent';

// An authentication failure renders an HTML page rather than the expected JSON, so a parse failure is a
// legitimate answer here and not an exception worth propagating
async function parseJson(res) {
  try {
    return await res.json();
  } catch (e) {
    return null;
  }
}

// Derived documents are built on demand and can take a while, so this is a three-state affordance rather
// than a link: offer to build them, spin while they are being built, then hand them over. A document is
// never fetched into the page - an SBOM runs to hundreds of megabytes, so the last state is a plain
// browser download.
export default {
  name: 'ReportDocuments',
  props: {
    pkgId: {type: Number, required: true},

    // Comes down with the rest of the report metadata, so the first render already knows the answer
    documents: {type: Object, default: null}
  },
  emits: ['error'],
  data() {
    return {
      busy: false,

      // Set once this component has an answer of its own (from the POST or its own poll), which is fresher
      // than the metadata refresh that feeds the prop. Dropped again as soon as the two can no longer
      // disagree, so the slow refresh stays in charge whenever nothing is happening here.
      override: null,
      timer: null
    };
  },
  computed: {
    building() {
      return this.current.state === 'building';
    },
    current() {
      return this.override ?? this.documents ?? {state: 'none'};
    },
    generateUrl() {
      return `/documents/${this.pkgId}`;
    },
    // The row is already labelled "Documents", so the verb carries it on its own
    label() {
      if (this.building) return 'Generating';
      return this.current.state === 'failed' ? 'Try again' : 'Generate';
    }
  },
  watch: {
    // Polling is tied to the state rather than to the click, so documents somebody else asked for (or ones
    // already being built when the page opened) are watched to completion just the same
    'current.state': {
      handler(state) {
        if (state === 'building') this.startPolling();
        else this.stopPolling();
      },
      immediate: true
    },
    documents() {
      if (this.timer === null && this.busy === false) this.override = null;
    }
  },
  beforeUnmount() {
    this.stopPolling();
  },
  methods: {
    async generate() {
      this.busy = true;
      try {
        const ua = new UserAgent({baseURL: window.location.href});
        const res = await ua.post(this.generateUrl);
        const data = await parseJson(res);

        if (res.isSuccess && data !== null) {
          this.override = data;
          return;
        }
        this.$emit('error', data?.error ?? `Document request failed (HTTP ${res.statusCode})`);
      } catch (err) {
        this.$emit('error', `Document request failed: ${err}`);
      } finally {
        this.busy = false;
      }
    },
    startPolling() {
      if (this.timer !== null) return;
      this.timer = setInterval(() => this.poll(), 2500);
    },
    stopPolling() {
      if (this.timer === null) return;
      clearInterval(this.timer);
      this.timer = null;
    },

    // The report page already has a cheap state endpoint for watching a rebuild, and the document state
    // rides along on it, so waiting for them costs no more than waiting for a reindex does
    async poll() {
      try {
        const ua = new UserAgent({baseURL: window.location.href});
        const res = await ua.get(`/reviews/report_state/${this.pkgId}`);
        if (res.isSuccess === false) return;

        const data = await parseJson(res);
        if (data?.documents) this.override = data.documents;
      } catch (err) {
        console.error('Document state request failed:', err);
      }
    }
  }
};
</script>

<style scoped>
.report-documents {
  display: flex;
  flex-direction: column;
  gap: 0.35rem;
}
.report-documents-row {
  align-items: center;
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
}

/* The comment field's Templates button, down to the shadow and the blue it turns on hover - the two are the
   same kind of thing (a small control parked in a text-heavy area) and there is no reason for the report
   page to grow a second dialect. Only the height differs: Templates sits in a toolbar with room around it,
   while this one has to fit a metadata row without pushing Documents and Shortname apart, so it matches
   the 15px/1.55 line box of the values around it instead. The ink is a shade lighter than Templates' for
   the same reason: the toolbar it sits in is empty, this one is surrounded by muted labels and asides,
   where near-black glyph and label read heavier than they do there. */
.report-documents-control {
  align-items: center;
  background: var(--cavil-surface-raised);
  border: 1px solid var(--cavil-border);
  border-radius: 6px;
  box-shadow: 0 1px 2px rgba(var(--cavil-shadow-alt-rgb), 0.08);
  color: var(--cavil-fg-muted-strong);
  cursor: pointer;
  display: inline-flex;
  font-size: 13px;
  gap: 0.35rem;
  height: 24px;

  /* Letters have more room below the baseline than above the cap, so centring the line box leaves the label
     sitting high; a pixel off the top of the content box puts the glyphs where the eye expects them */
  padding: 1px 0.5rem 0;
  transition:
    background-color 0.15s,
    box-shadow 0.15s,
    color 0.15s;
}
/* The list paints its links blue from an unscoped rule that outranks the class above. This one is a control,
   so it keeps the button ink and saves blue for hover like every other button on the page. */
.report-documents a.report-documents-control {
  color: var(--cavil-fg-muted-strong);
}
.report-documents a.report-documents-control:hover,
.report-documents-control:hover:not(:disabled) {
  background: var(--cavil-canvas);
  box-shadow: 0 2px 4px rgba(var(--cavil-shadow-alt-rgb), 0.12);
  color: var(--cavil-accent);

  /* The metadata list underlines its links on hover from an unscoped rule that reaches in here; this is a
     button, so it keeps its shape instead */
  text-decoration: none;
}
.report-documents a.report-documents-control:focus,
.report-documents-control:focus {
  border-color: var(--cavil-accent);
  box-shadow: 0 0 0 3px rgba(var(--cavil-accent-rgb), 0.3);
  color: var(--cavil-accent);
  outline: none;
  text-decoration: none;
}
.report-documents-control:disabled {
  color: var(--cavil-fg-muted);
  cursor: default;
}
.report-documents-ready span {
  font-family: ui-monospace, SFMono-Regular, Consolas, 'Liberation Mono', Menlo, monospace;

  /* The mono face reserves more room under the baseline than the label font does, and centring its line box
     spends that room above the characters instead, landing the filename a pixel higher than "Generate" sits
     in the same button. This puts it back on the line its neighbour uses. */
  position: relative;
  top: 1px;
}
.report-documents-size,
.report-documents-note {
  color: var(--cavil-fg-disabled);
  font-size: 12px;
}
</style>
