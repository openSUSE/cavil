<template>
  <CavilNoticePanel
    id="license-compatibility"
    title="Elevated risk"
    tone="warning"
    icon="fa-solid fa-triangle-exclamation"
  >
    <p class="cavil-notice-summary">
      This package contains licenses that the
      <a class="spdx-link" href="https://www.osadl.org/checklists" target="_blank" rel="noopener noreferrer">OSADL
      compatibility matrix</a> flags as not freely combinable. Each cell is OSADL's verdict for using the
      <em>column</em> license's material inside a work distributed under the <em>row</em> license. Click a marked cell
      for OSADL's explanation.
    </p>

    <div class="license-matrix-wrap">
      <table class="license-matrix">
        <thead>
          <tr>
            <th class="license-matrix-corner" scope="col"></th>
            <th v-for="(name, j) in licenses" :key="name" scope="col" class="license-matrix-colnum" :title="name">
              {{ j + 1 }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="(row, i) in licenses" :key="row">
            <th scope="row" class="license-matrix-rowhead">
              <span class="license-matrix-index">{{ i + 1 }}.</span>
              <a class="spdx-link" :href="spdxLicenseUrl(row)" target="_blank" rel="noopener noreferrer">{{ row }}</a>
            </th>
            <td
              v-for="(col, j) in licenses"
              :key="col"
              class="license-matrix-cell"
              :class="cellClass(row, col)"
              :title="cellTitle(row, col)"
              :aria-label="cellTitle(row, col)"
              @click="selectCell(row, col)"
            >
              <span v-if="i === j" class="license-matrix-self">—</span>
              <span v-else>{{ cellMark(row, col) }}</span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <div class="license-matrix-legend">
      <span><i class="license-matrix-swatch swatch-no"></i> No</span>
      <span><i class="license-matrix-swatch swatch-check"></i> Check dependency</span>
      <span><i class="license-matrix-swatch swatch-unknown"></i> Unknown</span>
      <span><i class="license-matrix-swatch swatch-yes"></i> Compatible</span>
    </div>

    <div v-if="selected" class="license-matrix-detail">
      <div class="license-matrix-detail-head">
        <a class="spdx-link" :href="spdxLicenseUrl(selected.outbound)" target="_blank" rel="noopener noreferrer">{{
          selected.outbound
        }}</a>
        <span class="license-matrix-arrow">◄</span>
        <a class="spdx-link" :href="spdxLicenseUrl(selected.inbound)" target="_blank" rel="noopener noreferrer">{{
          selected.inbound
        }}</a>
        <span class="license-matrix-verdict" :class="verdictClass(selected.compatibility)">{{
          selected.compatibility
        }}</span>
      </div>
      <p class="license-matrix-detail-body">{{ selected.explanation }}</p>
      <p class="license-matrix-detail-hint">
        OSADL verdict for using {{ selected.inbound }} material in a work under {{ selected.outbound }}.
      </p>
    </div>
  </CavilNoticePanel>
</template>

<script>
import CavilNoticePanel from './CavilNoticePanel.vue';

export default {
  name: 'LicenseCompatibilityMatrix',
  components: {CavilNoticePanel},
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
      const cell = this.cell(outbound, inbound);
      const verdict = cell === null ? 'Compatible' : cell.compatibility;
      return `${outbound} ◄ ${inbound}: ${verdict}`;
    },
    selectCell(outbound, inbound) {
      const cell = this.cell(outbound, inbound);
      if (outbound === inbound || cell === null) {
        this.selected = null;
        return;
      }
      this.selected = {outbound, inbound, compatibility: cell.compatibility, explanation: cell.explanation};
    },
    verdictClass(compatibility) {
      if (compatibility === 'No') return 'verdict-no';
      if (compatibility === 'Check dependency') return 'verdict-check';
      return 'verdict-unknown';
    },
    spdxLicenseUrl(name) {
      return `https://spdx.org/licenses/${encodeURIComponent(name)}.html`;
    }
  }
};
</script>

<style>
.license-matrix-wrap {
  overflow-x: auto;
  padding: 0.25rem 0.85rem 0.5rem;
}
.license-matrix {
  border-collapse: collapse;
  font-size: 13px;
}
.license-matrix th,
.license-matrix td {
  border: 1px solid #d8dee4;
}
.license-matrix-rowhead {
  font-weight: 500;
  padding: 0.2rem 0.6rem 0.2rem 0.35rem;
  text-align: left;
  white-space: nowrap;
}
.license-matrix-index {
  color: #8c959f;
  margin-right: 0.35rem;
  font-variant-numeric: tabular-nums;
}
.license-matrix-colnum {
  color: #57606a;
  font-variant-numeric: tabular-nums;
  font-weight: 500;
  min-width: 1.6rem;
  padding: 0.2rem 0.25rem;
  text-align: center;
}
.license-matrix-corner {
  background: #f6f8fa;
}
.license-matrix-cell {
  cursor: default;
  height: 1.6rem;
  min-width: 1.6rem;
  text-align: center;
}
.license-matrix-cell.cell-no,
.license-matrix-cell.cell-check,
.license-matrix-cell.cell-unknown {
  cursor: pointer;
}
.license-matrix-self {
  color: #d0d7de;
}
.cell-yes {
  background: #ffffff;
}
.cell-self {
  background: #f6f8fa;
}
.cell-no {
  background: #ffd8d3;
  color: #a40e26;
  font-weight: 600;
}
.cell-check {
  background: #fff4c9;
  color: #7d4e00;
  font-weight: 600;
}
.cell-unknown {
  background: #eef1f4;
  color: #6e7781;
}
.license-matrix-legend {
  color: #57606a;
  display: flex;
  flex-wrap: wrap;
  font-size: 12px;
  gap: 1rem;
  padding: 0.35rem 0.85rem 0.75rem;
}
.license-matrix-legend span {
  align-items: center;
  display: inline-flex;
  gap: 0.35rem;
}
.license-matrix-swatch {
  border: 1px solid #d8dee4;
  border-radius: 2px;
  display: inline-block;
  height: 0.75rem;
  width: 0.75rem;
}
.swatch-no {
  background: #ffd8d3;
}
.swatch-check {
  background: #fff4c9;
}
.swatch-unknown {
  background: #eef1f4;
}
.swatch-yes {
  background: #ffffff;
}
.license-matrix-detail {
  background: #ffffff;
  border-top: 1px solid #d8dee4;
  padding: 0.75rem 0.85rem;
}
.license-matrix-detail-head {
  align-items: center;
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
}
.license-matrix-arrow {
  color: #8c959f;
}
.license-matrix-verdict {
  border-radius: 999px;
  font-size: 12px;
  font-weight: 600;
  padding: 0.05rem 0.5rem;
}
.verdict-no {
  background: #ffd8d3;
  color: #a40e26;
}
.verdict-check {
  background: #fff4c9;
  color: #7d4e00;
}
.verdict-unknown {
  background: #eef1f4;
  color: #6e7781;
}
.license-matrix-detail-body {
  color: #1f2328;
  font-size: 13px;
  line-height: 1.5;
  margin: 0.5rem 0 0;
}
.license-matrix-detail-hint {
  color: #8c959f;
  font-size: 12px;
  margin: 0.35rem 0 0;
}
</style>
