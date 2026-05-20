<template>
  <div class="report-progress my-3" :style="{'--segment-count': labels.length}">
    <div class="progress-meta">
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
    stage: {type: Number, required: true}
  },
  data() {
    return {
      labels: ['Importing', 'Unpacking', 'Indexing', 'Finalizing']
    };
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
  background: #ffffff;
  border: 1px solid #d0d7de;
  border-radius: 6px;
  padding: 14px 16px 12px;
  box-shadow: 0 1px 0 rgba(27, 31, 36, 0.04);
}

.progress-meta {
  display: flex;
  justify-content: space-between;
  align-items: baseline;
  margin-bottom: 10px;
  gap: 12px;
}

.progress-title {
  color: #1f2328;
  font-size: 13px;
  font-weight: 600;
}

.progress-stage {
  color: #59636e;
  font-size: 12px;
  font-weight: 400;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.report-progress .progress {
  height: 22px;
  background: #eaeef2;
  border-radius: 6px;
  overflow: hidden;
  border: 0;
}

.report-progress .progress-bar {
  border-right: 1px solid rgba(255, 255, 255, 0.6);
  font-size: 11px;
  font-weight: 500;
  transition: background-color 0.2s ease;
}
.report-progress .progress-bar:last-child {
  border-right: 0;
}

.report-progress .progress-segment.is-done {
  background-color: #1f883d;
  color: #ffffff;
}
.report-progress .progress-segment.is-active {
  background-color: #54aeff;
  color: #0a3069;
  animation: cavil-progress-pulse 1.6s ease-in-out infinite;
}
.report-progress .progress-segment.is-pending {
  background-color: transparent;
  color: #59636e;
}

@keyframes cavil-progress-pulse {
  0%, 100% { background-color: #54aeff; }
  50% { background-color: #80ccff; }
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

@media (max-width: 767px) {
  .progress-bar {
    font-size: 10px;
  }
  .progress-stage {
    display: none;
  }
}
</style>
