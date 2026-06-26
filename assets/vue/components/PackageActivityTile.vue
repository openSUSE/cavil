<template>
  <article class="stats-activity-tile">
    <div class="stats-activity-header">
      <div>
        <div class="stats-tile-label">Packages</div>
        <div class="stats-activity-total">{{ total.toLocaleString() }}</div>
      </div>
      <span>{{ subtitle }}</span>
    </div>
    <svg
      class="stats-activity-chart"
      viewBox="0 0 240 72"
      role="img"
      :aria-label="chartSummary"
      preserveAspectRatio="none"
    >
      <line class="stats-activity-baseline" x1="0" y1="68" x2="240" y2="68"></line>
      <rect
        v-for="(bar, index) in bars"
        :key="`${bar.bucket}-${index}`"
        class="stats-activity-bar"
        :x="bar.x"
        :y="bar.y"
        :width="bar.width"
        :height="bar.height"
        :rx="barRadius"
        tabindex="0"
        :aria-label="barTooltip(bar)"
        @blur="hideActivityTooltip"
        @focus="showActivityTooltip(bar, $event)"
        @pointerenter="showActivityTooltip(bar, $event)"
        @pointerleave="hideActivityTooltip"
        @pointermove="moveActivityTooltip($event)"
      ></rect>
    </svg>
    <chart-tooltip
      v-if="activityTooltip"
      :x="activityTooltip.x"
      :y="activityTooltip.y"
      :title="activityTooltip.count"
      :subtitle="activityTooltip.label"
    ></chart-tooltip>
    <div class="stats-activity-axis">
      <span v-for="label in axisLabels" :key="label.key" :style="{left: `${label.position}%`}">{{ label.text }}</span>
    </div>
  </article>
</template>

<script>
import ChartTooltip from './ChartTooltip.vue';

export default {
  name: 'PackageActivityTile',
  components: {ChartTooltip},
  props: {
    labelMode: {type: String, default: 'hourly'},
    series: {type: Array, required: true},
    subtitle: {type: String, required: true}
  },
  data() {
    return {activityTooltip: null};
  },
  computed: {
    normalizedSeries() {
      return this.series.map(point => {
        const count = Number(point.count);
        return {
          bucket: point.bucket,
          count: Number.isFinite(count) ? Math.max(count, 0) : 0,
          label: point.label
        };
      });
    },
    total() {
      return this.normalizedSeries.reduce((sum, point) => sum + point.count, 0);
    },
    maxCount() {
      return Math.max(...this.normalizedSeries.map(point => point.count), 0);
    },
    barGap() {
      return this.labelMode === 'weekly' ? 8 : 2;
    },
    barRadius() {
      return this.labelMode === 'weekly' ? 2 : 1.5;
    },
    bars() {
      const count = this.normalizedSeries.length;
      if (count === 0) return [];

      const width = (240 - this.barGap * (count - 1)) / count;
      return this.normalizedSeries.map((point, index) => {
        const height = this.maxCount === 0 ? 2 : Math.max((point.count / this.maxCount) * 64, 2);
        return {...point, height, width, x: index * (width + this.barGap), y: 68 - height};
      });
    },
    axisLabels() {
      const count = this.normalizedSeries.length;
      if (count === 0) return [];

      const indexes = this.labelMode === 'weekly' ? this.weeklyLabelIndexes : this.hourlyLabelIndexes;
      return indexes.map(index => ({
        key: `${this.normalizedSeries[index].bucket}-${index}`,
        position: count === 1 ? 50 : (index / (count - 1)) * 100,
        text: this.normalizedSeries[index].label
      }));
    },
    hourlyLabelIndexes() {
      const indexes = [...Array(this.normalizedSeries.length).keys()].filter(index => index % 6 === 0);
      if (indexes[indexes.length - 1] !== this.normalizedSeries.length - 1)
        indexes.push(this.normalizedSeries.length - 1);
      return indexes;
    },
    weeklyLabelIndexes() {
      return [...Array(this.normalizedSeries.length).keys()];
    },
    chartSummary() {
      return `${this.total.toLocaleString()} packages imported over the ${this.subtitle}`;
    }
  },
  methods: {
    barTooltip(bar) {
      return `${bar.label}: ${bar.count.toLocaleString()} packages imported`;
    },
    showActivityTooltip(bar, event) {
      const position = this.activityTooltipPosition(event);
      this.activityTooltip = {...position, count: bar.count.toLocaleString(), label: bar.label};
    },
    moveActivityTooltip(event) {
      if (this.activityTooltip === null) return;
      this.activityTooltip = {...this.activityTooltip, ...this.activityTooltipPosition(event)};
    },
    hideActivityTooltip() {
      this.activityTooltip = null;
    },
    activityTooltipPosition(event) {
      const tile = event.currentTarget.closest('.stats-activity-tile');
      const rect = tile.getBoundingClientRect();
      const fallbackX = rect.width / 2;
      const fallbackY = rect.height / 2;
      const x = event.clientX ? event.clientX - rect.left : fallbackX;
      const y = event.clientY ? event.clientY - rect.top : fallbackY;
      return {
        x: Math.min(Math.max(x, 24), rect.width - 24),
        y: Math.min(Math.max(y, 24), rect.height - 24)
      };
    }
  }
};
</script>

<style scoped>
.stats-activity-tile {
  background: #fff;
  border: 1px solid #d0d7de;
  border-radius: 6px;
  box-shadow: 0 1px 2px rgba(27, 31, 36, 0.04);
  color: #24292f;
  display: grid;
  gap: 0.8rem;
  grid-column: span 3;
  min-width: 0;
  padding: 1rem;
  position: relative;
}

.stats-activity-header {
  align-items: start;
  display: flex;
  justify-content: space-between;
}

.stats-tile-label {
  color: #57606a;
  font-size: 0.78rem;
  font-weight: 600;
  letter-spacing: 0;
  text-transform: uppercase;
}

.stats-activity-total {
  color: #24292f;
  font-size: 1.8rem;
  font-weight: 600;
  line-height: 1.1;
  margin-top: 0.25rem;
}

.stats-activity-header span,
.stats-activity-axis {
  color: #57606a;
  font-size: 0.78rem;
  font-weight: 500;
}

.stats-activity-chart {
  height: 72px;
  overflow: visible;
  width: 100%;
}

.stats-activity-baseline {
  stroke: #d8dee4;
  stroke-width: 1;
}

.stats-activity-bar {
  fill: #0969da;
}

.stats-activity-bar:focus {
  outline: none;
  stroke: #24292f;
  stroke-width: 1;
}

.stats-activity-axis {
  height: 1rem;
  position: relative;
}

.stats-activity-axis span {
  position: absolute;
  transform: translateX(-50%);
  white-space: nowrap;
}

.stats-activity-axis span:first-child {
  transform: translateX(0);
}

.stats-activity-axis span:last-child {
  transform: translateX(-100%);
}

@media (max-width: 767.98px) {
  .stats-activity-tile {
    grid-column: span 1;
  }
}
</style>
