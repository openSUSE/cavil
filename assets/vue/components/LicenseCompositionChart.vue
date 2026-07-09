<template>
  <section v-if="distribution.length > 0" :id="id" class="license-composition-card mb-3">
    <header class="license-composition-header">
      <h3>{{ title }}</h3>
      <div class="license-composition-total">
        <span class="license-composition-total-value">{{ total }}</span>
        <span class="license-composition-total-label">{{ total === 1 ? singularLabel : pluralLabel }}</span>
      </div>
    </header>
    <div class="license-composition-body">
      <div class="license-composition-chart">
        <svg class="license-composition-donut" viewBox="0 0 120 120" :aria-label="chartSummary" role="img">
          <circle class="license-composition-donut-track" cx="60" cy="60" r="44" />
          <circle
            v-for="entry in distribution"
            :key="`slice-${entry.name}`"
            class="license-composition-slice"
            cx="60"
            cy="60"
            r="44"
            pathLength="100"
            :stroke="entry.color"
            :stroke-dasharray="`${entry.share} ${100 - entry.share}`"
            :stroke-dashoffset="-entry.offset"
            tabindex="0"
            :aria-label="sliceLabel(entry)"
            @blur="hideTooltip"
            @focus="showTooltip(entry, $event)"
            @pointerenter="showTooltip(entry, $event)"
            @pointerleave="hideTooltip"
            @pointermove="moveTooltip($event)"
          ></circle>
        </svg>
        <div v-if="dominantEntry" class="license-composition-chart-label">
          <b>{{ dominantEntry.percent }}%</b>
          <span v-html="dominantEntry.name_html"></span>
        </div>
        <div
          v-if="tooltip"
          class="license-composition-tooltip"
          :style="{left: `${tooltip.x}px`, top: `${tooltip.y}px`}"
        >
          <b>{{ tooltip.percent }}%</b>
          <span>{{ tooltip.name }}</span>
        </div>
      </div>
      <ol class="license-composition-list">
        <li v-for="entry in distribution" :key="entry.name" class="license-composition-item">
          <div class="license-composition-item-header">
            <span class="license-composition-swatch" :style="{backgroundColor: entry.color}"></span>
            <span class="license-composition-name" v-html="entry.name_html"></span>
            <span class="license-composition-percent">{{ entry.percent }}%</span>
          </div>
          <div class="license-composition-meter" aria-hidden="true">
            <span :style="{width: `${entry.share}%`, backgroundColor: entry.color}"></span>
          </div>
        </li>
      </ol>
    </div>
  </section>
</template>

<script>
const LICENSE_CHART_COLORS = ['#0969da', '#1a7f37', '#9a6700', '#cf222e', '#8250df', '#bf3989', '#57606a', '#2da44e'];

export default {
  name: 'LicenseCompositionChart',
  props: {
    entries: {type: Array, required: true},
    id: {type: String, required: true},
    limit: {type: Number, default: 0},
    pluralLabel: {type: String, required: true},
    singularLabel: {type: String, required: true},
    title: {type: String, required: true}
  },
  data() {
    return {tooltip: null};
  },
  computed: {
    distribution() {
      const total = this.entries.reduce((sum, entry) => {
        const count = Number(entry.count);
        return sum + (Number.isFinite(count) ? count : 0);
      }, 0);
      if (this.entries.length === 0 || total === 0) return [];

      let offset = 0;
      const sorted = this.entries
        .map(entry => {
          const count = Number(entry.count);
          const files = Number.isFinite(count) ? count : 0;
          return {
            name: entry.name,
            name_html: entry.name_html ?? entry.name,
            files,
            percent: Math.round((files / total) * 100),
            share: (files / total) * 100
          };
        })
        .filter(entry => entry.files > 0)
        .sort((a, b) => b.files - a.files || a.name.localeCompare(b.name));

      const capped = this.limit > 0 && sorted.length > this.limit ? sorted.slice(0, this.limit) : sorted;
      if (this.limit > 0 && sorted.length > this.limit) {
        const miscFiles = sorted.slice(this.limit).reduce((sum, entry) => sum + entry.files, 0);
        capped.push({
          name: 'Misc',
          name_html: 'Misc',
          files: miscFiles,
          percent: Math.round((miscFiles / total) * 100),
          share: (miscFiles / total) * 100
        });
      }

      return capped.map((entry, index) => {
        const slice = {...entry, offset, color: LICENSE_CHART_COLORS[index % LICENSE_CHART_COLORS.length]};
        offset += entry.share;
        return slice;
      });
    },
    dominantEntry() {
      return this.distribution[0] || null;
    },
    chartSummary() {
      return this.distribution.map(entry => this.sliceLabel(entry)).join(', ');
    },
    total() {
      return this.distribution.reduce((sum, entry) => sum + entry.files, 0);
    }
  },
  methods: {
    sliceLabel(entry) {
      return `${entry.name}: ${entry.percent}%`;
    },
    showTooltip(entry, event) {
      const position = this.tooltipPosition(event);
      this.tooltip = {...position, name: entry.name, percent: entry.percent};
    },
    moveTooltip(event) {
      if (this.tooltip === null) return;
      this.tooltip = {...this.tooltip, ...this.tooltipPosition(event)};
    },
    hideTooltip() {
      this.tooltip = null;
    },
    tooltipPosition(event) {
      const chart = event.currentTarget.closest('.license-composition-chart');
      const rect = chart.getBoundingClientRect();
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
.license-composition-card {
  border: 1px solid #d0d7de;
  border-radius: 6px;
  overflow: visible;
}
.license-composition-header {
  align-items: center;
  background: #f6f8fa;
  border-bottom: 1px solid #d0d7de;
  border-radius: 6px 6px 0 0;
  display: flex;
  gap: 1rem;
  justify-content: space-between;
  padding: 0.75rem 1rem;
}
.license-composition-header h3 {
  font-size: 1rem;
  line-height: 1.3;
  margin: 0;
}
.license-composition-total {
  align-items: flex-end;
  background: #fff;
  border: 1px solid #d0d7de;
  border-radius: 6px;
  display: flex;
  gap: 0.35rem;
  padding: 0.25rem 0.5rem;
  white-space: nowrap;
}
.license-composition-total-value {
  color: #24292f;
  font-size: 1rem;
  font-weight: 700;
  line-height: 1.1;
}
.license-composition-total-label {
  color: #57606a;
  font-size: 12px;
  font-weight: 600;
  line-height: 1.2;
}
.license-composition-body {
  align-items: center;
  background: #fff;
  border-radius: 0 0 6px 6px;
  display: grid;
  gap: 1.25rem;
  grid-template-columns: minmax(180px, 240px) minmax(0, 1fr);
  padding: 1rem;
}
.license-composition-chart {
  align-items: center;
  aspect-ratio: 1;
  display: flex;
  justify-content: center;
  justify-self: center;
  max-width: 240px;
  min-width: 180px;
  padding: 2rem;
  position: relative;
  width: 100%;
}
.license-composition-donut {
  filter: drop-shadow(0 1px 2px rgba(27, 31, 36, 0.08));
  inset: 0;
  overflow: visible;
  position: absolute;
  transform: rotate(-90deg);
}
.license-composition-donut-track,
.license-composition-slice {
  fill: none;
  stroke-width: 24;
}
.license-composition-donut-track {
  stroke: #eaeef2;
}
.license-composition-slice {
  cursor: help;
  transition:
    opacity 0.12s ease,
    stroke-width 0.12s ease;
}
.license-composition-slice:hover {
  opacity: 0.88;
  stroke-width: 26;
}
.license-composition-chart-label {
  align-items: center;
  background: #fff;
  border-radius: 50%;
  box-shadow: inset 0 0 0 1px rgba(27, 31, 36, 0.08);
  color: #24292f;
  display: flex;
  flex-direction: column;
  gap: 0.1rem;
  height: 50%;
  justify-content: center;
  line-height: 1.15;
  max-width: 50%;
  min-width: 0;
  position: relative;
  text-align: center;
  z-index: 1;
}
.license-composition-chart-label b {
  font-size: 1.8rem;
  letter-spacing: 0;
}
.license-composition-chart-label span {
  color: #57606a;
  font-size: 12px;
  font-weight: 600;
  max-width: 100%;
  overflow-wrap: anywhere;
}
.license-composition-tooltip {
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
  overflow-wrap: anywhere;
  padding: 0.35rem 0.5rem;
  pointer-events: none;
  position: absolute;
  text-align: center;
  transform: translate(-50%, calc(-100% - 10px));
  width: 180px;
  z-index: 2;
}
.license-composition-tooltip b {
  font-size: 13px;
  letter-spacing: 0;
}
.license-composition-tooltip span {
  max-width: 100%;
}
.license-composition-list {
  display: grid;
  gap: 0.5rem;
  list-style: none;
  margin: 0;
  padding: 0;
}
.license-composition-item {
  display: grid;
  gap: 0.35rem;
}
.license-composition-item-header {
  align-items: center;
  display: grid;
  gap: 0.75rem;
  grid-template-columns: auto minmax(0, 1fr) auto;
}
.license-composition-swatch {
  border-radius: 50%;
  height: 10px;
  width: 10px;
}
.license-composition-name {
  color: #24292f;
  font-weight: 600;
  min-width: 0;
  overflow-wrap: anywhere;
}
.license-composition-percent {
  color: #24292f;
  font-size: 13px;
  font-weight: 700;
  font-variant-numeric: tabular-nums;
  min-width: 3.5em;
  text-align: right;
}
.license-composition-meter {
  background: #eaeef2;
  border-radius: 999px;
  height: 8px;
  margin-left: 1.35rem;
  overflow: hidden;
}
.license-composition-meter span {
  border-radius: inherit;
  display: block;
  height: 100%;
  min-width: 3px;
}
@media (max-width: 767.98px) {
  .license-composition-body {
    grid-template-columns: 1fr;
  }
  .license-composition-chart {
    max-width: 220px;
  }
}
</style>
