<template>
  <section id="license-compatibility" class="license-matrix-card mb-3">
    <header class="license-matrix-header">
      <h3>License compatibility</h3>
      <div class="license-matrix-legend" aria-label="Compatibility verdict legend">
        <span class="license-matrix-legend-item"><i class="license-matrix-swatch cell-no">✕</i> Incompatible</span>
        <span class="license-matrix-legend-item"
          ><i class="license-matrix-swatch cell-check">?</i> Check dependency</span
        >
        <span class="license-matrix-legend-item"><i class="license-matrix-swatch cell-unknown">·</i> Unknown</span>
        <span class="license-matrix-legend-item"><i class="license-matrix-swatch cell-yes"></i> Compatible</span>
      </div>
    </header>

    <div class="license-matrix-body">
      <p class="license-matrix-intro">
        Each cell is OSADL's verdict on using the column license in a work under the row license. Click a marked cell
        for the explanation.
      </p>

      <div class="license-matrix-grid-wrap">
        <table class="license-matrix-grid">
          <thead>
            <tr>
              <th class="license-matrix-corner" scope="col"></th>
              <th v-for="(name, j) in licenses" :key="name" scope="col" class="license-matrix-colhead" :title="name">
                {{ j + 1 }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="(row, i) in licenses" :key="row">
              <th scope="row" class="license-matrix-rowhead">
                <span class="license-matrix-rowhead-index">{{ i + 1 }}</span>
                <span class="license-matrix-rowhead-name">{{ row }}</span>
              </th>
              <td
                v-for="col in licenses"
                :key="col"
                class="license-matrix-cell"
                :class="[cellClass(row, col), {'is-active': isActive(row, col)}]"
                :title="cellTitle(row, col)"
                :aria-label="cellTitle(row, col)"
                @click="selectCell(row, col)"
              >
                <span aria-hidden="true">{{ cellMark(row, col) }}</span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <div v-if="selected" class="license-matrix-detail">
      <div class="license-matrix-detail-bar" :class="verdictBarClass(selected.compatibility)">
        <strong class="license-matrix-verdict">{{ verdictLabel(selected.compatibility) }}</strong>
        <span class="license-matrix-connector">using</span>
        <a
          class="spdx-link license-matrix-detail-name"
          :href="spdxLicenseUrl(selected.inbound)"
          target="_blank"
          rel="noopener noreferrer"
          >{{ selected.inbound }}</a
        >
        <span class="license-matrix-connector">in a work under</span>
        <a
          class="spdx-link license-matrix-detail-name"
          :href="spdxLicenseUrl(selected.outbound)"
          target="_blank"
          rel="noopener noreferrer"
          >{{ selected.outbound }}</a
        >
      </div>
      <p class="license-matrix-detail-body">{{ selected.explanation }}</p>
    </div>
  </section>
</template>

<script>
export default {
  name: 'LicenseCompatibilityMatrix',
  props: {
    licenses: {type: Array, default: () => []},
    matrix: {type: Object, default: () => ({})}
  },
  data() {
    return {selected: null};
  },
  methods: {
    cell(outbound, inbound) {
      return this.matrix?.[outbound]?.[inbound] ?? null;
    },
    cellClass(outbound, inbound) {
      if (outbound === inbound) return 'cell-self';
      const cell = this.cell(outbound, inbound);
      if (cell === null) return 'cell-yes';
      if (cell.compatibility === 'No') return 'cell-no';
      if (cell.compatibility === 'Check dependency') return 'cell-check';
      return 'cell-unknown';
    },
    cellMark(outbound, inbound) {
      const cell = this.cell(outbound, inbound);
      if (cell === null) return '';
      if (cell.compatibility === 'No') return '✕';
      if (cell.compatibility === 'Check dependency') return '?';
      return '·';
    },
    cellTitle(outbound, inbound) {
      if (outbound === inbound) return outbound;
      return `Using ${inbound} under ${outbound}: ${this.verdictLabel(this.cell(outbound, inbound)?.compatibility)}`;
    },
    verdictLabel(compatibility) {
      if (compatibility === 'No') return 'Incompatible';
      if (compatibility === 'Check dependency') return 'Check dependency';
      if (compatibility === 'Unknown') return 'Unknown';
      return 'Compatible';
    },
    verdictBarClass(compatibility) {
      if (compatibility === 'No') return 'bar-no';
      if (compatibility === 'Check dependency') return 'bar-check';
      return 'bar-unknown';
    },
    isActive(outbound, inbound) {
      return this.selected !== null && this.selected.outbound === outbound && this.selected.inbound === inbound;
    },
    selectCell(outbound, inbound) {
      const cell = this.cell(outbound, inbound);
      if (outbound === inbound || cell === null) {
        this.selected = null;
        return;
      }
      this.selected = {outbound, inbound, compatibility: cell.compatibility, explanation: cell.explanation};
    },
    spdxLicenseUrl(name) {
      return `https://spdx.org/licenses/${encodeURIComponent(name)}.html`;
    }
  }
};
</script>

<style scoped>
.license-matrix-card {
  border: 1px solid #d0d7de;
  border-radius: 6px;
  min-width: 0;
  overflow: hidden;
}
.license-matrix-header {
  align-items: center;
  background: #f6f8fa;
  border-bottom: 1px solid #d0d7de;
  border-radius: 6px 6px 0 0;
  display: flex;
  gap: 1rem;
  justify-content: space-between;
  padding: 0.65rem 0.85rem 0.65rem 1rem;
}
.license-matrix-header h3 {
  font-size: 1rem;
  line-height: 1.3;
  margin: 0;
}
.license-matrix-body {
  background: #fff;
  padding: 1rem;
}
.license-matrix-intro {
  color: #57606a;
  font-size: 13px;
  line-height: 1.5;
  margin: 0 0 0.75rem;
}

/* Heatmap grid — GitHub contribution-graph aesthetic */
.license-matrix-grid-wrap {
  overflow-x: auto;
}
.license-matrix-grid {
  border-collapse: separate;
  border-spacing: 3px;
  font-size: 12px;
}
.license-matrix-corner {
  background: #fff;
  left: 0;
  position: sticky;
  z-index: 2;
}
.license-matrix-colhead {
  color: #57606a;
  font-variant-numeric: tabular-nums;
  font-weight: 500;
  min-width: 1.5rem;
  padding: 0.15rem 0.2rem;
  text-align: center;
}
.license-matrix-rowhead {
  background: #fff;
  font-weight: 400;
  left: 0;
  padding: 0.15rem 0.75rem 0.15rem 0;
  position: sticky;
  text-align: left;
  white-space: nowrap;
  z-index: 1;
}
.license-matrix-rowhead-index {
  color: #57606a;
  display: inline-block;
  font-variant-numeric: tabular-nums;
  margin-right: 0.5rem;
  min-width: 1.1rem;
  text-align: right;
}
.license-matrix-rowhead-name {
  color: #1f2328;
}

.license-matrix-cell {
  border: 1px solid transparent;
  border-radius: 3px;
  height: 1.2rem;
  line-height: 1.2rem;
  min-width: 1.5rem;
  text-align: center;
}
/* Colour classes — shared by the grid cells and the legend swatches (colour only, no behaviour) */
.cell-self {
  background: #f6f8fa;
}
.cell-yes {
  background: #ebedf0;
}
.cell-no {
  background: #ffebe9;
  border-color: #ffcecb;
  color: #cf222e;
  font-weight: 600;
}
.cell-check {
  background: #fff8c5;
  border-color: #d4a72c66;
  color: #7d4e00;
  font-weight: 600;
}
.cell-unknown {
  background: #eaeef2;
  border-color: rgba(110, 119, 129, 0.25);
  color: #57606a;
}

/* Only the grid cells are interactive; the legend swatches reuse the colour classes above */
.license-matrix-cell.cell-no,
.license-matrix-cell.cell-check,
.license-matrix-cell.cell-unknown {
  cursor: pointer;
}
.license-matrix-cell.cell-no:hover,
.license-matrix-cell.cell-check:hover,
.license-matrix-cell.cell-unknown:hover {
  filter: brightness(0.95);
}
.license-matrix-cell.is-active {
  border-color: #24292f;
}

.license-matrix-legend {
  align-items: center;
  background: #fff;
  border: 1px solid #d0d7de;
  border-radius: 6px;
  color: #57606a;
  display: flex;
  flex-wrap: wrap;
  font-size: 12px;
  gap: 0.65rem;
  justify-content: flex-end;
  margin-left: auto;
  padding: 0.25rem 0.45rem;
}
.license-matrix-legend-item {
  align-items: center;
  display: inline-flex;
  gap: 0.3rem;
  white-space: nowrap;
}
.license-matrix-swatch {
  align-items: center;
  border: 1px solid transparent;
  border-radius: 3px;
  display: inline-flex;
  font-size: 10px;
  font-style: normal;
  height: 1rem;
  justify-content: center;
  width: 1rem;
}

.license-matrix-detail {
  border-top: 1px solid #d0d7de;
}

/* A deliberate two-band element: a verdict-tinted title bar over the explanation body. The bar's
   colour matches the cell that was clicked, tying the panel to the grid. */
.license-matrix-detail-bar {
  align-items: center;
  border-bottom: 1px solid #d0d7de;
  color: #1f2328;
  display: flex;
  flex-wrap: wrap;
  font-size: 13px;
  gap: 0.4rem;
  padding: 0.55rem 1rem;
}
.bar-no {
  background: #ffebe9;
  border-bottom-color: #ffcecb;
}
.bar-check {
  background: #fff8c5;
  border-bottom-color: #d4a72c66;
}
.bar-unknown {
  background: #eaeef2;
  border-bottom-color: #d0d7de;
}
.license-matrix-verdict {
  color: #1f2328;
  font-weight: 600;
}
.license-matrix-connector {
  color: #57606a;
}
.license-matrix-detail-name {
  color: #1f2328;
  font-weight: 600;
}
.license-matrix-detail-body {
  background: #f6f8fa;
  color: #1f2328;
  font-size: 13px;
  line-height: 1.5;
  margin: 0;
  padding: 0.85rem 1rem;
}
</style>
