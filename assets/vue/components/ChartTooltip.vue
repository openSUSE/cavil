<template>
  <div class="chart-tooltip" :style="{left: `${x}px`, top: `${y}px`, width}">
    <b>{{ title }}</b>
    <span>{{ subtitle }}</span>
  </div>
</template>

<script>
export default {
  name: 'ChartTooltip',
  props: {
    subtitle: {type: String, required: true},
    title: {type: String, required: true},
    width: {type: String, default: '150px'},
    x: {type: Number, required: true},
    y: {type: Number, required: true}
  }
};
</script>

<style scoped>
.chart-tooltip {
  align-items: center;
  background: #24292f;
  border-radius: 6px;
  box-shadow: 0 8px 24px rgba(140, 149, 159, 0.2);
  color: #fff;
  display: flex;
  flex-direction: column;
  font-size: 12px;
  font-weight: 600;
  gap: 0.1rem;
  line-height: 1.35;
  padding: 0.35rem 0.5rem;
  pointer-events: none;
  position: absolute;
  text-align: center;
  transform: translate(-50%, calc(-100% - 10px));
  z-index: 2;
}

.chart-tooltip b {
  font-size: 13px;
  letter-spacing: 0;
}
</style>
