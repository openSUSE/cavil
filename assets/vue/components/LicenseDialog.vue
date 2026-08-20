<template>
  <div class="modal fade license-modal" ref="modal" tabindex="-1" aria-labelledby="licenseDialogLabel">
    <div class="modal-dialog modal-dialog-scrollable modal-dialog-centered">
      <div class="modal-content">
        <div class="modal-header">
          <span class="license-eyebrow">License</span>
          <h2 class="license-id" id="licenseDialogLabel">{{ license }}</h2>
          <!-- Only an SPDX identifier has a page there; a curated text has no canonical source to offer -->
          <a
            v-if="isSpdx"
            class="license-source"
            :href="`https://spdx.org/licenses/${license}.html`"
            target="_blank"
            rel="noopener noreferrer"
            >spdx.org <i class="fa-solid fa-arrow-up-right-from-square"></i
          ></a>
          <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
        </div>
        <!-- The scrollport is the body, and Bootstrap only ever focuses the modal itself, so PageDown
             and the arrow keys are dead until the body is given focus -->
        <div class="modal-body" ref="body" tabindex="-1">
          <LicenseText v-if="license" :key="license" :license="license" />
        </div>
      </div>
    </div>
  </div>
</template>

<script>
import LicenseText from './LicenseText.vue';
import {Modal} from 'bootstrap';

export default {
  name: 'LicenseDialog',
  components: {LicenseText},
  data() {
    return {license: null, isSpdx: false, modal: null};
  },
  mounted() {
    this.$refs.modal.addEventListener('shown.bs.modal', () => this.$refs.body.focus());
  },
  methods: {
    open(license, isSpdx) {
      this.license = license;
      this.isSpdx = isSpdx;
      if (!this.modal) this.modal = Modal.getOrCreateInstance(this.$refs.modal);
      this.modal.show();
    }
  }
};
</script>

<style>
.license-modal {
  --bs-modal-bg: var(--cavil-canvas);
}
/* No shadow reads on a near-black page, so the sheet has to sit above the canvas by tone and a border */
[data-bs-theme='dark'] .license-modal {
  --bs-modal-bg: var(--cavil-canvas-tint);
  --bs-modal-border-color: var(--cavil-border);
}

/* Sized to the 70ch column plus its margins */
.license-modal .modal-dialog {
  --bs-modal-margin: 1.75rem;
  --bs-modal-width: 46rem;
}
.license-modal .modal-content {
  --bs-modal-border-radius: 12px;
  box-shadow: 0 8px 32px rgba(var(--cavil-shadow-alt-rgb), 0.24);
}

.license-modal .modal-header {
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
.license-eyebrow,
.license-id,
.license-source {
  line-height: 1;
}
.license-eyebrow {
  color: var(--cavil-fg-muted);
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.06em;
  text-transform: uppercase;
}
.license-id {
  font-family: ui-monospace, SFMono-Regular, Consolas, 'Liberation Mono', monospace;
  font-size: 15px;
  font-weight: 600;
  margin: 0;
  min-width: 0;
  overflow-wrap: anywhere;
}
.license-source {
  color: var(--cavil-fg-muted);
  font-size: 13px;
  text-decoration: none;
  white-space: nowrap;
}
.license-source:hover {
  color: var(--cavil-accent);
}

/* Bootstrap's own box is 28px and would set the header's content height, stranding the baseline row at
   the top of it; sized to the identifier instead, and centred because it has no baseline of its own */
.license-modal .btn-close {
  align-self: center;
  box-sizing: border-box;
  font-size: 12px;
  height: 16px;
  margin: 0 0 0 auto;
  padding: 0;
  width: 16px;
}

.license-modal .license-source {
  margin-left: 0.35rem;
}

.license-modal .modal-body {
  padding: 1.25rem 1.75rem 2rem;
}
/* Focused only to be scrollable, so it must not read as an active field */
.license-modal .modal-body:focus-visible {
  outline: none;
}
</style>
