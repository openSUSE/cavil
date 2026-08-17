<template>
  <div class="modal fade spdx-license-modal" ref="modal" tabindex="-1" aria-labelledby="spdxLicenseLabel">
    <div class="modal-dialog modal-dialog-scrollable modal-dialog-centered">
      <div class="modal-content">
        <div class="modal-header">
          <span class="spdx-license-eyebrow">License</span>
          <h2 class="spdx-license-id" id="spdxLicenseLabel">{{ spdxId }}</h2>
          <a
            class="spdx-license-source"
            :href="`https://spdx.org/licenses/${spdxId}.html`"
            target="_blank"
            rel="noopener noreferrer"
            >spdx.org <i class="fa-solid fa-arrow-up-right-from-square"></i
          ></a>
          <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
        </div>
        <!-- The scrollport is the body, and Bootstrap only ever focuses the modal itself, so PageDown
             and the arrow keys are dead until the body is given focus -->
        <div class="modal-body" ref="body" tabindex="-1">
          <SpdxLicenseText v-if="spdxId" :key="spdxId" :spdx-id="spdxId" />
        </div>
      </div>
    </div>
  </div>
</template>

<script>
import SpdxLicenseText from './SpdxLicenseText.vue';
import {Modal} from 'bootstrap';

export default {
  name: 'SpdxLicenseDialog',
  components: {SpdxLicenseText},
  data() {
    return {spdxId: null, modal: null};
  },
  mounted() {
    this.$refs.modal.addEventListener('shown.bs.modal', () => this.$refs.body.focus());
  },
  methods: {
    open(spdxId) {
      this.spdxId = spdxId;
      if (!this.modal) this.modal = Modal.getOrCreateInstance(this.$refs.modal);
      this.modal.show();
    }
  }
};
</script>

<style>
.spdx-license-modal {
  --bs-modal-bg: var(--cavil-canvas);
}
/* No shadow reads on a near-black page, so the sheet has to sit above the canvas by tone and a border */
[data-bs-theme='dark'] .spdx-license-modal {
  --bs-modal-bg: var(--cavil-canvas-tint);
  --bs-modal-border-color: var(--cavil-border);
}

/* Sized to the 70ch column plus its margins */
.spdx-license-modal .modal-dialog {
  --bs-modal-margin: 1.75rem;
  --bs-modal-width: 46rem;
}
.spdx-license-modal .modal-content {
  --bs-modal-border-radius: 12px;
  box-shadow: 0 8px 32px rgba(var(--cavil-shadow-alt-rgb), 0.24);
}

.spdx-license-modal .modal-header {
  align-items: baseline;
  background: var(--bs-modal-bg);
  border-bottom-color: var(--cavil-border);
  /* One flat row: a nested flex container contributes a synthesized baseline, so grouping the eyebrow
     with the identifier would stop all three from sharing one */
  gap: 0.55rem;
  /* Bootstrap spreads the children apart; the close button's own auto margin does the job */
  justify-content: flex-start;
  padding: 0.85rem 1.75rem;
}
/* line-height 1 on all three: baseline alignment stacks the tallest leading above and below the shared
   baseline, which pushes the row off centre when the sizes differ */
.spdx-license-eyebrow,
.spdx-license-id,
.spdx-license-source {
  line-height: 1;
}
.spdx-license-eyebrow {
  color: var(--cavil-fg-muted);
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.06em;
  text-transform: uppercase;
}
.spdx-license-id {
  font-family: ui-monospace, SFMono-Regular, Consolas, 'Liberation Mono', monospace;
  font-size: 15px;
  font-weight: 600;
  margin: 0;
  min-width: 0;
  overflow-wrap: anywhere;
}
.spdx-license-source {
  color: var(--cavil-fg-muted);
  font-size: 13px;
  text-decoration: none;
  white-space: nowrap;
}
.spdx-license-source:hover {
  color: var(--cavil-accent);
}

/* Bootstrap's own box is 28px and would set the header's content height, stranding the baseline row at
   the top of it; sized to the identifier instead, and centred because it has no baseline of its own */
.spdx-license-modal .btn-close {
  align-self: center;
  box-sizing: border-box;
  font-size: 12px;
  height: 16px;
  margin: 0 0 0 auto;
  padding: 0;
  width: 16px;
}

.spdx-license-modal .spdx-license-source {
  margin-left: 0.35rem;
}

.spdx-license-modal .modal-body {
  padding: 1.25rem 1.75rem 2rem;
}
/* Focused only to be scrollable, so it must not read as an active field */
.spdx-license-modal .modal-body:focus-visible {
  outline: none;
}
</style>
