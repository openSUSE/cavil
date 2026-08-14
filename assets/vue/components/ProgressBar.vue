<template>
  <div
    class="report-progress"
    :class="compact ? 'report-progress-compact' : 'my-3'"
    :style="{'--segment-count': labels.length}"
  >
    <div v-if="!compact" class="progress-meta">
      <span class="progress-title">Preparing report</span>
      <span class="progress-stage">{{ currentLabel }} · Step {{ normalizedStage }} of {{ labels.length }}</span>
    </div>
    <div class="progress">
      <div
        v-for="(label, idx) in labels"
        :key="label"
        class="progress-bar"
        :class="barClass(idx + 1)"
        role="progressbar"
        :style="{width: segmentWidth}"
        :aria-valuenow="idx + 1 <= stage ? 100 : 0"
        aria-valuemin="0"
        aria-valuemax="100"
        :aria-label="label"
      >
        <span>
          <i v-if="idx + 1 < stage" class="fa-solid fa-check me-1"></i>
          <i v-else-if="idx + 1 === stage" class="fa-solid fa-spinner fa-pulse me-1"></i>
          {{ label }}
        </span>
      </div>
    </div>
  </div>
</template>

<script>
export default {
  name: 'ProgressBar',
  props: {
    stage: {type: Number, required: true},

    // Muted, chrome-less variant for a bar that sits beside a report the reviewer is still reading, rather
    // than standing in for one that does not exist yet
    compact: {type: Boolean, default: false},
    labels: {type: Array, default: () => ['Importing', 'Unpacking', 'Indexing', 'Finalizing']}
  },
  computed: {
    normalizedStage() {
      return Math.max(1, Math.min(this.stage, this.labels.length));
    },
    currentLabel() {
      return this.labels[this.normalizedStage - 1];
    },
    segmentWidth() {
      return `${100 / this.labels.length}%`;
    }
  },
  methods: {
    barClass(idx) {
      if (idx < this.stage) return 'progress-segment is-done';
      if (idx === this.stage) return 'progress-segment is-active';
      return 'progress-segment is-pending';
    }
  }
};
</script>

<style scoped>
.report-progress {
  background: var(--cavil-canvas);
  border: 1px solid var(--cavil-border);
  border-radius: 6px;
  padding: 14px 16px 12px;
  box-shadow: 0 1px 0 rgba(var(--cavil-shadow-rgb), 0.04);
}

.progress-meta {
  display: flex;
  justify-content: space-between;
  align-items: baseline;
  margin-bottom: 10px;
  gap: 12px;
}

.progress-title {
  color: var(--cavil-fg);
  font-size: 13px;
  font-weight: 600;
}

.progress-stage {
  color: var(--cavil-fg-muted-alt);
  font-size: 12px;
  font-weight: 400;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.report-progress .progress {
  height: 22px;
  background: var(--cavil-neutral-bg);
  border-radius: 6px;
  overflow: hidden;
  border: 0;
}

.report-progress .progress-bar {
  /* Divider between segments of a saturated bar, so it stays white in both themes. */
  border-right: 1px solid rgba(255, 255, 255, 0.6);
  font-size: 11px;
  font-weight: 500;
  transition: background-color 0.2s ease;
}
.report-progress .progress-bar:last-child {
  border-right: 0;
}

.report-progress .progress-segment.is-done {
  background-color: var(--cavil-success-emphasis);
  color: var(--cavil-on-accent);
}
.report-progress .progress-segment.is-active {
  background-color: var(--cavil-accent-vivid);
  color: var(--cavil-accent-deep);
  animation: cavil-progress-pulse 1.6s ease-in-out infinite;
}
.report-progress .progress-segment.is-pending {
  background-color: transparent;
  color: var(--cavil-fg-muted-alt);
}

@keyframes cavil-progress-pulse {
  0%,
  100% {
    background-color: var(--cavil-accent-vivid);
  }
  50% {
    background-color: var(--cavil-accent-2);
  }
}

@media (prefers-reduced-motion: reduce) {
  .report-progress .progress-segment.is-active {
    animation: none;
  }
}

.progress-bar span {
  padding: 0 6px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

/* Beside a live report the bar is a status line, not a panel: no card, shorter, and in tints rather than
   the full-strength colours, so it never competes with the report for attention. */
.report-progress-compact {
  background: transparent;
  border: 0;
  border-radius: 0;
  box-shadow: none;
  padding: 0;
}

.report-progress-compact .progress {
  background: var(--cavil-tint-5);
  border-radius: 4px;
  height: 16px;
}

.report-progress-compact .progress-bar {
  font-size: 10px;
  font-weight: 500;
}

.report-progress-compact .progress-segment.is-done {
  background-color: var(--cavil-success-tint-2);
  color: var(--cavil-success);
}

.report-progress-compact .progress-segment.is-active {
  animation: cavil-progress-pulse-muted 1.6s ease-in-out infinite;
  background-color: var(--cavil-accent-tint-5);
  color: var(--cavil-accent-deep);
}

.report-progress-compact .progress-segment.is-pending {
  color: var(--cavil-grey-5);
}

@keyframes cavil-progress-pulse-muted {
  0%,
  100% {
    background-color: var(--cavil-accent-tint-5);
  }
  50% {
    background-color: var(--cavil-accent-tint-4);
  }
}

@media (prefers-reduced-motion: reduce) {
  .report-progress-compact .progress-segment.is-active {
    animation: none;
  }
}

@media (max-width: 767px) {
  .progress-bar {
    font-size: 10px;
  }
  .progress-stage {
    display: none;
  }
}
</style>
