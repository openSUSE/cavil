<template>
  <div class="report-progress my-3" :style="{'--segment-count': labels.length}">
    <div class="progress-meta">
      <span class="progress-title">Preparing Report</span>
      <span class="progress-stage">Step {{ normalizedStage }} / {{ labels.length }}</span>
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
      >
        <span>
          <i v-if="idx + 1 < stage" class="fa-solid fa-check me-1"></i>
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
    segmentWidth() {
      return `${100 / this.labels.length}%`;
    }
  },
  methods: {
    barClass(idx) {
      if (idx < this.stage) return 'bg-success';
      if (idx === this.stage) return 'progress-bar-striped progress-bar-animated bg-info';
      return 'bg-light text-muted';
    }
  }
};
</script>

<style scoped>
.report-progress {
  background: var(--bs-tertiary-bg, #f8f9fa);
  border: 1px solid var(--bs-border-color, #dee2e6);
  border-radius: 0.9rem;
  padding: 0.85rem 0.95rem 0.75rem;
}

.progress-meta {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 0.55rem;
  padding: 0 0.2rem;
}

.progress-title {
  color: var(--bs-emphasis-color, #212529);
  font-size: 0.8rem;
  font-weight: 700;
  letter-spacing: 0.06em;
  text-transform: uppercase;
}

.progress-stage {
  color: var(--bs-secondary-color, #6c757d);
  font-size: 0.78rem;
  font-weight: 600;
}

.report-progress .progress {
  height: 1.75rem;
  border: 1px solid var(--bs-border-color, #dee2e6);
}

.report-progress .progress-bar.bg-light.text-muted {
  background-color: var(--bs-secondary-bg-subtle, #e2e3e5) !important;
  color: var(--bs-secondary-color, #6c757d) !important;
}

.progress-bar span {
  padding: 0 0.2rem;
  white-space: nowrap;
}

@media (max-width: 767px) {
  .progress-bar {
    font-size: 0.66rem;
  }
}
</style>
