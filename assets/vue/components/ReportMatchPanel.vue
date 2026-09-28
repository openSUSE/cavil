<template>
  <div
    :id="'file-details-' + panel.fileId"
    class="report-match-panel cavil-reveal"
    :class="{'is-loaded': panel.source && !panel.unavailable}"
  >
    <div class="report-match-inner">
      <div v-if="panel.unavailable" class="report-match-note">
        The sources are being unpacked, this file becomes readable again once reindexing finishes.
      </div>
      <div v-else-if="!panel.source" class="report-match-note report-match-loading">Loading matches&hellip;</div>
      <div v-else class="source">
        <FileSource
          v-bind="$attrs"
          :lines="panel.source.lines"
          :file-id="panel.fileId"
          :package-id="pkgId"
          :filename="panel.source.filename"
          :packname="panel.source.name"
          :file-url="fileUrl"
          :has-admin-role="hasAdminRole"
          :has-contributor-role="hasContributorRole"
          :read-only="readOnly"
          :pending-actions="pendingActions"
          :inline-editor="inlineEditor"
        />
      </div>
      <button v-if="remaining > 0" type="button" class="report-match-more" @click="$emit('show-more')">
        {{ moreLabel }}
      </button>
    </div>
  </div>
</template>

<script>
import FileSource from './FileSource.vue';
import {fileViewUrl} from '../helpers/links.js';

// The matches one report row stands for, in one file: a license at one risk, or the unresolved snippets.
// Every FileSource event the host listens for passes straight through.
export default {
  name: 'ReportMatchPanel',
  components: {FileSource},
  inheritAttrs: false,
  props: {
    panel: {type: Object, required: true},
    pkgId: {type: Number, required: true},
    step: {type: Number, required: true},
    hasAdminRole: {type: Boolean, default: false},
    hasContributorRole: {type: Boolean, default: false},
    readOnly: {type: Boolean, default: false},
    pendingActions: {type: Array, default: () => []},
    inlineEditor: {type: Object, default: null}
  },
  emits: ['show-more'],
  computed: {
    total() {
      return this.panel.source?.total ?? 0;
    },
    shown() {
      return Math.min(this.total, this.panel.groups);
    },
    remaining() {
      return this.total - this.shown;
    },
    moreLabel() {
      const next = Math.min(this.step, this.remaining);
      const [one, many] = this.panel.list === 'unresolved' ? ['snippet', 'snippets'] : ['match', 'matches'];
      const label = `Show ${next} more ${next === 1 ? one : many}`;
      return this.remaining > next ? `${label} (${this.remaining} remaining)` : label;
    },
    fileUrl() {
      return fileViewUrl(this.pkgId, this.panel.path);
    }
  }
};
</script>

<style>
/* Reveals once the matches arrive, not when the panel mounts */
.report-match-panel.is-loaded:not(.cavil-reveal-leave-active) {
  animation: cavil-reveal-open 150ms ease-out;
}
.report-match-inner {
  padding: 0.3rem 0 0.2rem;
}
/* Fast responses never show it */
.report-match-loading {
  animation: report-match-delay 150ms step-end;
}
@keyframes report-match-delay {
  from {
    visibility: hidden;
  }
}
.report-match-more:hover,
.report-match-more:focus-visible {
  color: var(--cavil-accent-strong);
}
.report-match-panel .source {
  background: var(--cavil-canvas);
  border: 1px solid var(--cavil-border-muted) !important;
  border-radius: 6px;
  margin: 0;
}
.report-match-note {
  color: var(--cavil-fg-muted-alt);
  font-size: 12px;
}
.report-match-more {
  appearance: none;
  background: none;
  border: 0;
  color: var(--cavil-fg-muted);
  font: inherit;
  font-size: 12px;
  margin-top: 0.25rem;
  padding: 0;
}
</style>
