<template>
  <article class="stats-donut-tile">
    <div class="stats-donut-copy">
      <div class="stats-tile-label">{{ title }}</div>
      <slot name="actions"></slot>
    </div>
    <div class="stats-donut-wrap">
      <svg class="stats-donut" viewBox="0 0 120 120" role="img" :aria-label="chartSummary">
        <circle class="stats-donut-track" cx="60" cy="60" r="44"></circle>
        <circle
          v-for="slice in chartSlices"
          :key="slice.label"
          class="stats-donut-slice"
          cx="60"
          cy="60"
          r="44"
          pathLength="100"
          :stroke="slice.color"
          :stroke-dasharray="slice.dasharray"
          :stroke-dashoffset="-slice.offset"
        ></circle>
      </svg>
      <div class="stats-donut-center">
        <b>{{ roundedSlicePercent }}%</b>
        <span>{{ centerLabel }}</span>
      </div>
    </div>
    <dl class="stats-donut-legend">
      <div>
        <dt><span class="stats-swatch stats-swatch-active"></span>{{ totalLabel }}</dt>
        <dd>{{ total.toLocaleString() }}</dd>
      </div>
      <div v-for="slice in chartSlices" :key="`legend-${slice.label}`">
        <dt><span class="stats-swatch" :style="{backgroundColor: slice.color}"></span>{{ slice.label }}</dt>
        <dd>{{ slice.value.toLocaleString() }}</dd>
      </div>
    </dl>
  </article>
</template>

<script>
export default {
  name: 'DonutStatTile',
  props: {
    centerLabel: {type: String, default: 'activity'},
    centerValue: {type: Number, default: null},
    slices: {type: Array, required: true},
    title: {type: String, required: true},
    total: {type: Number, required: true},
    totalLabel: {type: String, required: true}
  },
  computed: {
    chartSlices() {
      if (this.total <= 0) return [];

      let offset = 0;
      return this.slices
        .map(slice => {
          const value = Number(slice.value);
          return {...slice, value: Number.isFinite(value) ? Math.max(value, 0) : 0};
        })
        .filter(slice => slice.value > 0)
        .map(slice => {
          const percent = Math.min((slice.value / this.total) * 100, 100);
          const chartSlice = {...slice, percent, offset, dasharray: `${percent} ${100 - percent}`};
          offset += percent;
          return chartSlice;
        });
    },
    slicePercent() {
      if (this.centerValue !== null) {
        if (this.total <= 0) return 0;
        return Math.min((Math.max(this.centerValue, 0) / this.total) * 100, 100);
      }

      return Math.min(
        this.chartSlices.reduce((sum, slice) => sum + slice.percent, 0),
        100
      );
    },
    roundedSlicePercent() {
      return Math.round(this.slicePercent);
    },
    chartSummary() {
      const slices = this.chartSlices.map(slice => `${slice.value.toLocaleString()} ${slice.label}`).join(', ');
      return `${this.total.toLocaleString()} ${this.totalLabel}${slices === '' ? '' : `: ${slices}`}`;
    }
  }
};
</script>

<style scoped>
.stats-donut-tile {
  align-items: center;
  background: #fff;
  border: 1px solid #d0d7de;
  border-radius: 6px;
  box-shadow: 0 1px 2px rgba(27, 31, 36, 0.04);
  color: #24292f;
  display: grid;
  gap: 0.9rem 1rem;
  grid-column: span 2;
  grid-template-columns: minmax(0, 1fr) 128px;
  min-width: 0;
  padding: 1rem;
}

.stats-donut-copy {
  align-self: start;
  display: flex;
  flex-direction: column;
}

.stats-tile-label {
  color: #57606a;
  font-size: 0.78rem;
  font-weight: 600;
  letter-spacing: 0;
  text-transform: uppercase;
}

.stats-donut-wrap {
  align-items: center;
  aspect-ratio: 1;
  display: flex;
  justify-content: center;
  position: relative;
  width: 128px;
}

.stats-donut {
  filter: drop-shadow(0 1px 2px rgba(27, 31, 36, 0.08));
  inset: 0;
  overflow: visible;
  position: absolute;
  transform: rotate(-90deg);
}

.stats-donut-track,
.stats-donut-slice {
  fill: none;
  stroke-width: 24;
}

.stats-donut-track {
  stroke: #1f883d;
}

.stats-donut-center {
  align-items: center;
  background: #fff;
  border-radius: 50%;
  box-shadow: inset 0 0 0 1px rgba(27, 31, 36, 0.08);
  display: flex;
  flex-direction: column;
  height: 50%;
  justify-content: center;
  line-height: 1.15;
  position: relative;
  text-align: center;
  width: 50%;
  z-index: 1;
}

.stats-donut-center b {
  font-size: 1.15rem;
  letter-spacing: 0;
}

.stats-donut-center span {
  color: #57606a;
  font-size: 0.62rem;
  font-weight: 600;
  max-width: 60px;
  overflow-wrap: anywhere;
}

.stats-donut-legend {
  border-top: 1px solid #d8dee4;
  display: grid;
  gap: 0.45rem;
  grid-column: 1 / -1;
  margin: 0;
  padding-top: 0.75rem;
}

.stats-donut-legend div {
  align-items: center;
  display: flex;
  justify-content: space-between;
}

.stats-donut-legend dt {
  align-items: center;
  color: #57606a;
  display: flex;
  font-size: 0.82rem;
  font-weight: 500;
  gap: 0.4rem;
}

.stats-donut-legend dd {
  color: #24292f;
  font-size: 0.86rem;
  font-weight: 600;
  margin: 0;
}

.stats-swatch {
  border-radius: 999px;
  display: inline-block;
  height: 0.6rem;
  width: 0.6rem;
}

.stats-swatch-active {
  background: #1f883d;
}

@media (max-width: 575.98px) {
  .stats-donut-tile {
    grid-column: span 1;
    grid-template-columns: minmax(0, 1fr);
  }

  .stats-donut-wrap {
    justify-self: center;
  }
}
</style>
