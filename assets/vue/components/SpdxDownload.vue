<template>
  <div class="spdx-download">
    <span v-if="current.state === 'unavailable'" class="spdx-download-note">not available</span>
    <template v-else>
      <!-- The same control throughout: asking for the report, waiting for it and taking it home are one
           affordance in three states, so only the glyph and the label change under the cursor -->
      <a
        v-if="current.state === 'ready'"
        class="spdx-download-control spdx-download-ready"
        :href="downloadUrl"
        :download="fileName"
      >
        <i class="fa-solid fa-file-arrow-down" aria-hidden="true"></i>
        <span>{{ fileName }}</span>
      </a>
      <button
        v-else
        type="button"
        class="spdx-download-control"
        :disabled="building || busy"
        :aria-busy="building"
        @click="generate"
      >
        <i :class="building ? 'fa-solid fa-rotate fa-spin' : 'fa-solid fa-file-arrow-down'" aria-hidden="true"></i>
        <span>{{ label }}</span>
      </button>
      <span v-if="current.state === 'ready' && current.size" class="spdx-download-size">{{ current.size }}</span>
      <span v-if="current.state === 'failed'" class="spdx-download-note">last attempt failed</span>
    </template>
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

// SPDX reports are built on demand and can take a while, so this is a three-state affordance rather than a
// link: offer to build one, spin while it is being built, then hand it over. The report itself is never
// fetched into the page - these run to hundreds of megabytes, so the last state is a plain browser download.
export default {
  name: 'SpdxDownload',
  props: {
    pkgId: {type: Number, required: true},

    // Comes down with the rest of the report metadata, so the first render already knows the answer
    spdx: {type: Object, default: null}
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
      return this.override ?? this.spdx ?? {state: 'none'};
    },
    downloadUrl() {
      return `/spdx/${this.pkgId}`;
    },
    fileName() {
      return `${this.pkgId}.spdx.json`;
    },
    // The row is already labelled "SPDX report", so the verb carries it on its own
    label() {
      if (this.building) return 'Generating';
      return this.current.state === 'failed' ? 'Try again' : 'Generate';
    }
  },
  watch: {
    // Polling is tied to the state rather than to the click, so a report somebody else asked for (or one
    // already being built when the page opened) is watched to completion just the same
    'current.state': {
      handler(state) {
        if (state === 'building') this.startPolling();
        else this.stopPolling();
      },
      immediate: true
    },
    spdx() {
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
        const res = await ua.post(this.downloadUrl);
        const data = await parseJson(res);

        if (res.isSuccess && data !== null) {
          this.override = data;
          return;
        }
        this.$emit('error', data?.error ?? `SPDX report request failed (HTTP ${res.statusCode})`);
      } catch (err) {
        this.$emit('error', `SPDX report request failed: ${err}`);
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

    // The report page already has a cheap state endpoint for watching a rebuild, and the SPDX state rides
    // along on it, so waiting for a report costs no more than waiting for a reindex does
    async poll() {
      try {
        const ua = new UserAgent({baseURL: window.location.href});
        const res = await ua.get(`/reviews/report_state/${this.pkgId}`);
        if (res.isSuccess === false) return;

        const data = await parseJson(res);
        if (data?.spdx) this.override = data.spdx;
      } catch (err) {
        console.error('SPDX state request failed:', err);
      }
    }
  }
};
</script>

<style scoped>
.spdx-download {
  align-items: center;
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
}

/* The comment field's Templates button, down to the shadow and the blue it turns on hover - the two are the
   same kind of thing (a small control parked in a text-heavy area) and there is no reason for the report
   page to grow a second dialect. Only the height differs: Templates sits in a toolbar with room around it,
   while this one has to fit a metadata row without pushing SPDX report and Shortname apart, so it matches
   the 15px/1.55 line box of the values around it instead. The ink is a shade lighter than Templates' for
   the same reason: the toolbar it sits in is empty, this one is surrounded by muted labels and asides,
   where near-black glyph and label read heavier than they do there. */
.spdx-download-control {
  align-items: center;
  background: rgba(255, 255, 255, 0.92);
  border: 1px solid #d0d7de;
  border-radius: 6px;
  box-shadow: 0 1px 2px rgba(31, 35, 40, 0.08);
  color: #424a53;
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
.spdx-download a.spdx-download-control {
  color: #424a53;
}
.spdx-download a.spdx-download-control:hover,
.spdx-download-control:hover:not(:disabled) {
  background: #ffffff;
  box-shadow: 0 2px 4px rgba(31, 35, 40, 0.12);
  color: #0969da;

  /* The metadata list underlines its links on hover from an unscoped rule that reaches in here; this is a
     button, so it keeps its shape instead */
  text-decoration: none;
}
.spdx-download a.spdx-download-control:focus,
.spdx-download-control:focus {
  border-color: #0969da;
  box-shadow: 0 0 0 3px rgba(9, 105, 218, 0.3);
  color: #0969da;
  outline: none;
  text-decoration: none;
}
.spdx-download-control:disabled {
  color: #57606a;
  cursor: default;
}
.spdx-download-ready span {
  font-family: ui-monospace, SFMono-Regular, Consolas, 'Liberation Mono', Menlo, monospace;

  /* The mono face reserves more room under the baseline than the label font does, and centring its line box
     spends that room above the characters instead, landing the filename a pixel higher than "Generate" sits
     in the same button. This puts it back on the line its neighbour uses. */
  position: relative;
  top: 1px;
}
.spdx-download-size,
.spdx-download-note {
  color: #8c959f;
  font-size: 12px;
}
</style>
