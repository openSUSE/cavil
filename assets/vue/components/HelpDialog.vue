<template>
  <Teleport to="body">
    <!-- Same sheet as the license view, so help reads as something opened on top of the report, not part of it -->
    <div class="modal fade help-modal" ref="modal" tabindex="-1" :aria-label="`Help: ${title}`">
      <div class="modal-dialog modal-dialog-scrollable modal-dialog-centered">
        <div class="modal-content">
          <div class="modal-header">
            <span class="license-eyebrow">Help</span>
            <h2 class="help-modal-title">{{ title }}</h2>
            <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
          </div>
          <div class="modal-body"><slot></slot></div>
        </div>
      </div>
    </div>
  </Teleport>
</template>

<script>
import {Modal} from 'bootstrap';

export default {
  name: 'HelpDialog',
  props: {title: {type: String, required: true}},
  methods: {
    // Bootstrap only hands focus back to data-bs-toggle triggers
    open() {
      const trigger = document.activeElement;
      this.$refs.modal.addEventListener('hidden.bs.modal', () => trigger?.focus(), {once: true});
      Modal.getOrCreateInstance(this.$refs.modal).show();
    }
  }
};
</script>

<style>
.help-modal.modal .modal-dialog {
  --bs-modal-width: 38rem;
}
.help-modal-title {
  font-size: 15px;
  font-weight: 600;
  line-height: 1;
  margin: 0;
}
.help-modal .modal-body {
  color: var(--cavil-fg);
  font-size: 14px;
  line-height: 1.55;
}
.help-modal .modal-body p {
  margin: 0 0 0.85rem;
}
.help-modal .modal-body > :last-child {
  margin-bottom: 0;
}
.help-modal .modal-body code {
  color: inherit;
}
.help-modal .help-example {
  border: 1px solid var(--cavil-border-muted);
  border-radius: 6px;
  margin: 0 0 0.85rem;
  overflow: hidden;
}
.help-example-file {
  background: var(--cavil-canvas-subtle);
  border-bottom: 1px solid var(--cavil-border-muted);
  color: var(--cavil-fg-subtle);
  font-size: 12px;
  padding: 0.3rem 0.65rem;
}
.help-example pre {
  color: var(--cavil-fg-code);
  font-size: 12px;
  margin: 0;
  padding: 0.5rem 0.65rem;
  white-space: pre-wrap;
}
</style>
