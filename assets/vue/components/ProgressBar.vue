<template>
  <div class="report-progress my-3">
    <div class="progress">
      <div
        v-for="(label, idx) in labels"
        :key="label"
        class="progress-bar"
        :class="barClass(idx + 1)"
        role="progressbar"
        :style="{width: '25%'}"
        :aria-valuenow="idx + 1 <= stage ? 100 : 0"
        aria-valuemin="0"
        aria-valuemax="100"
      >
        <span><i v-if="idx + 1 < stage" class="fa-solid fa-check me-1"></i>{{ label }}</span>
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
      labels: ['Importing', 'Unpacking', 'Indexing', 'Generating Report']
    };
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
.report-progress .progress {
  height: 1.75rem;
  border: 1px solid #dee2e6;
}
</style>
