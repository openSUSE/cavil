<template>
  <section id="license-compatibility" class="license-matrix-card mb-3">
    <header class="license-matrix-header">
      <h3>License compatibility</h3>
      <div class="license-matrix-controls">
        <div v-if="hasProximity" class="license-matrix-mode" role="group" aria-label="Grid colouring">
          <button
            type="button"
            class="license-matrix-mode-btn"
            :class="{'is-on': colorMode === 'verdict'}"
            @click="colorMode = 'verdict'"
          >
            Verdict
          </button>
          <button
            type="button"
            class="license-matrix-mode-btn"
            :class="{'is-on': colorMode === 'likelihood'}"
            @click="colorMode = 'likelihood'"
          >
            Likelihood
          </button>
        </div>
        <button v-if="canShrink" type="button" class="license-matrix-toggle" @click="showAll = !showAll">
          <span class="license-matrix-toggle-verb">{{ toggleVerb }}</span>
          <strong class="license-matrix-toggle-count">{{ toggleCount }}</strong>
          <span class="license-matrix-toggle-unit">{{ toggleUnit }}</span>
        </button>
      </div>
    </header>

    <div class="license-matrix-body">
      <div class="license-matrix-grid-wrap">
        <table class="license-matrix-grid">
          <thead>
            <tr>
              <th class="license-matrix-corner" scope="col"></th>
              <th
                v-for="(name, j) in visibleLicenses"
                :key="name"
                scope="col"
                class="license-matrix-colhead"
                :class="selectedAxisClass('inbound', name)"
              >
                {{ j + 1 }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="(row, i) in visibleLicenses" :key="row">
              <th scope="row" class="license-matrix-rowhead" :class="selectedAxisClass('outbound', row)">
                <span class="license-matrix-rowhead-index">{{ i + 1 }}</span>
                <span class="license-matrix-rowhead-name">{{ row }}</span>
              </th>
              <td
                v-for="(col, j) in visibleLicenses"
                :key="col"
                class="license-matrix-cell"
                :class="[
                  cellClass(row, col),
                  {
                    'is-active': isActive(row, col),
                    'is-mutual': isMutual(row, col),
                    'mode-likelihood': colorMode === 'likelihood'
                  },
                  mutualCornerClass(i, j)
                ]"
                :aria-label="cellTitle(row, col)"
                @pointerenter="showMatrixTooltip(row, col, $event)"
                @pointermove="moveMatrixTooltip($event)"
                @pointerleave="hideMatrixTooltip"
                @click="selectCell(row, col)"
              >
                <span class="license-matrix-mark" aria-hidden="true" :style="markStyle(row, col)">{{
                  cellMark(row, col)
                }}</span>
              </td>
            </tr>
          </tbody>
        </table>
        <div v-if="hovered" class="license-matrix-tooltip" :style="{left: `${hovered.x}px`, top: `${hovered.y}px`}">
          <strong>{{ verdictLabel(hovered.compatibility) }}</strong>
          <span class="license-matrix-tooltip-line">
            <span class="license-matrix-tooltip-label">Using</span>
            <span>{{ hovered.inbound }}</span>
          </span>
          <span class="license-matrix-tooltip-line">
            <span class="license-matrix-tooltip-label">Under</span>
            <span>{{ hovered.outbound }}</span>
          </span>
        </div>
      </div>
    </div>

    <div v-if="selected" class="license-matrix-detail">
      <div class="license-matrix-detail-bar" :class="verdictBarClass(selected.compatibility)">
        <span class="license-matrix-detail-title">
          <strong class="license-matrix-verdict">{{ verdictLabel(selected.compatibility) }}</strong>
          <span class="license-matrix-connector">using</span>
          <button
            type="button"
            class="spdx-link license-matrix-detail-name"
            :data-spdx="selected.inbound"
            v-text="selected.inbound"
          ></button>
          <span class="license-matrix-connector">in a work under</span>
          <button
            type="button"
            class="spdx-link license-matrix-detail-name"
            :data-spdx="selected.outbound"
            v-text="selected.outbound"
          ></button>
        </span>
        <span class="license-matrix-detail-label">OSADL verdict</span>
      </div>
      <p class="license-matrix-detail-body">{{ selected.explanation }}</p>
      <div class="license-matrix-where">
        <span class="license-matrix-where-head">
          <span class="license-matrix-where-label">Where</span>
          <span class="license-matrix-where-verdict">{{ whereSummary }}</span>
          <span v-if="whereTag" class="license-matrix-where-tag">{{ whereTag }}</span>
          <span v-if="scopeTag" class="license-matrix-where-tag">{{ scopeTag }}</span>
        </span>
        <ul v-if="selectedFiles.length" class="license-matrix-file-list">
          <li v-for="f in selectedFiles" :key="f">
            <a class="license-matrix-file-link" :href="fileHref(f)" target="_blank" rel="noopener noreferrer"
              ><FilePath :path="f"
            /></a>
          </li>
        </ul>
      </div>
    </div>

    <div v-if="colorMode === 'verdict'" class="license-matrix-legend" aria-label="Compatibility verdict legend">
      <span class="license-matrix-legend-item"><i class="license-matrix-swatch cell-no"></i> Incompatible</span>
      <span class="license-matrix-legend-item"
        ><i class="license-matrix-swatch swatch-mutual"></i> Both directions</span
      >
      <span class="license-matrix-legend-item"><i class="license-matrix-swatch cell-check"></i> Check dependency</span>
      <span class="license-matrix-legend-item"><i class="license-matrix-swatch cell-unknown"></i> Unknown</span>
      <span class="license-matrix-legend-item"><i class="license-matrix-swatch cell-yes"></i> Compatible</span>
    </div>
    <div v-else class="license-matrix-legend" aria-label="Combination likelihood legend">
      <span class="license-matrix-legend-item"><i class="license-matrix-swatch swatch-file"></i> Same file</span>
      <span class="license-matrix-legend-item"
        ><i class="license-matrix-swatch swatch-deep"></i> Deep shared directory</span
      >
      <span class="license-matrix-legend-item"
        ><i class="license-matrix-swatch swatch-shared"></i> Shared directory</span
      >
      <span class="license-matrix-legend-item"
        ><i class="license-matrix-swatch swatch-root"></i> Package root only</span
      >
      <span class="license-matrix-legend-item"
        ><i class="license-matrix-swatch swatch-peripheral"></i> Tests / docs / vendored</span
      >
    </div>
  </section>
</template>

<script>
import FilePath from './FilePath.vue';
import {fileViewUrl} from '../helpers/links.js';

export default {
  name: 'LicenseCompatibilityMatrix',
  components: {FilePath},
  props: {
    licenses: {type: Array, default: () => []},
    matrix: {type: Object, default: () => ({})},
    // Symmetric per-pair proximity {a: {b: {confidence, same_file, lca_depth, tier, files}}} (keyed
    // a < b) - drives the "Likelihood" colour mode and the detail panel's "Where" block. pkgId builds the
    // file-browser links.
    proximity: {type: Object, default: () => ({})},
    pkgId: {type: [Number, String], default: null}
  },
  data() {
    return {selected: null, showAll: false, hovered: null, colorMode: 'verdict'};
  },
  created() {
    // Default to the focused (conflicts-only) view for large matrices; show everything when the grid
    // is small or when there are no both-way conflicts to focus on.
    this.showAll = this.conflictLicenses.length === 0 || this.licenses.length <= 12;
  },
  computed: {
    // Reorder the axes so mutually-incompatible licenses sit next to each other. Each connected
    // component of the "No in both directions" graph becomes a contiguous run, so its conflicts read as
    // one merged block instead of tiles scattered across the grid. Deterministic: components by size
    // then name, members by conflict degree then name, unrelated licenses appended alphabetically.
    orderedLicenses() {
      const licenses = this.licenses;
      const adjacency = new Map(licenses.map(l => [l, new Set()]));
      for (const a of licenses) {
        for (const b of licenses) {
          if (a >= b) continue;
          if (this.isMutual(a, b)) {
            adjacency.get(a).add(b);
            adjacency.get(b).add(a);
          }
        }
      }

      const seen = new Set();
      const components = [];
      for (const start of licenses) {
        if (seen.has(start) || adjacency.get(start).size === 0) continue;
        const stack = [start];
        const component = [];
        seen.add(start);
        while (stack.length) {
          const node = stack.pop();
          component.push(node);
          for (const next of adjacency.get(node)) {
            if (!seen.has(next)) {
              seen.add(next);
              stack.push(next);
            }
          }
        }
        component.sort((a, b) => adjacency.get(b).size - adjacency.get(a).size || (a < b ? -1 : 1));
        components.push(component);
      }
      components.sort((a, b) => b.length - a.length || (a[0] < b[0] ? -1 : 1));

      const clustered = components.flat();
      const rest = licenses.filter(l => !seen.has(l)).sort((a, b) => (a < b ? -1 : 1));
      return [...clustered, ...rest];
    },
    // Licenses that take part in at least one "No in both directions" pair - the genuinely
    // unshippable-either-way conflicts. The clustered order from orderedLicenses is preserved.
    conflictLicenses() {
      return this.orderedLicenses.filter(l => this.licenses.some(o => o !== l && this.isMutual(l, o)));
    },
    visibleLicenses() {
      return this.showAll ? this.orderedLicenses : this.conflictLicenses;
    },
    // Only offer the toggle when it would actually change the view.
    canShrink() {
      return this.conflictLicenses.length > 0 && this.conflictLicenses.length < this.licenses.length;
    },
    // Toggle label split into verb / bold count / unit so the number echoes the composition chart's
    // "big bold value + small word" stat, instead of a parenthesised count.
    toggleVerb() {
      return this.showAll ? 'Show' : 'Show all';
    },
    toggleCount() {
      return this.showAll ? this.conflictLicenses.length : this.licenses.length;
    },
    toggleUnit() {
      return this.showAll ? 'conflicts' : 'licenses';
    },
    // The mode toggle only appears when there is proximity data to colour by.
    hasProximity() {
      return Object.keys(this.proximity || {}).length > 0;
    },
    selectedProximity() {
      return this.selected ? this.pairProximity(this.selected.outbound, this.selected.inbound) : null;
    },
    // The representative files for the selected pair, de-duplicated (a same-file hit lists one path twice).
    selectedFiles() {
      const p = this.selectedProximity;
      if (!p || !Array.isArray(p.files)) return [];
      return [...new Set(p.files.filter(Boolean))];
    },
    whereSummary() {
      const p = this.selectedProximity;
      if (!p) return '';
      // The two never share a file: one license is present only as an unresolved-snippet guess. We still
      // link that unresolved match's file below so the reviewer can open and judge it.
      if (p.no_colocation) return 'Not co-located - one license appears only as an unresolved match:';
      if (p.same_file) return 'Both licenses in one file';
      if ((p.lca_depth ?? 0) >= 1) return 'Closest files share a directory';
      return 'Only co-located at the package root';
    },
    // A confidence caveat on a co-location - none for a real match, and none for a not-co-located pair
    // (its summary already says "unresolved match").
    whereTag() {
      const p = this.selectedProximity;
      if (!p || p.no_colocation) return null;
      if (p.confidence === 2) return 'via a folded snippet';
      if (p.confidence === 1) return 'via an unresolved match';
      return null;
    },
    // Vendored code is named separately from tests and docs: it can be linked into the build, so it is not
    // dismissible the way a fixture is.
    scopeTag() {
      const p = this.selectedProximity;
      if (!p || p.no_colocation || !p.tier) return null;
      return p.tier === 1 ? 'vendored' : 'tests / docs / examples';
    }
  },
  methods: {
    // Proximity is stored once per unordered pair (a < b); look it up regardless of which axis is outbound.
    pairProximity(a, b) {
      const [x, y] = a < b ? [a, b] : [b, a];
      return this.proximity?.[x]?.[y] ?? null;
    },
    isFlagged(outbound, inbound) {
      return outbound !== inbound && this.cell(outbound, inbound) !== null;
    },
    // Every "Where" file opens in the file browser in a new tab. Consistency matters more than an inline
    // preview here: proximity can point at files beyond the report's per-license display cap that have no
    // inline block, and mixing inline-for-some with dead-for-others is worse than one predictable behaviour.
    fileHref(path) {
      return fileViewUrl(this.pkgId, path);
    },
    // Likelihood colouring: a categorical heat scale (distinct hues, not shades of one colour - those blur
    // into a soup on a big grid) plus a size cue, so the genuinely-combined pairs stand out of a cool/grey
    // mass. same-file is a large red dot, a deep shared directory hot orange, a shallow one amber, root-only
    // a small cool grey-blue, and peripheral (tests/docs/vendored) a small neutral grey out of the ramp.
    markStyle(outbound, inbound) {
      if (this.colorMode !== 'likelihood' || !this.isFlagged(outbound, inbound)) return null;
      const p = this.pairProximity(outbound, inbound);
      let color, size;
      // Heat ramp, hottest first: same-file, then deeper shared dir, then shallow. One hue stepped by
      // lightness, so the tier order is legible as a ramp rather than as three colours to memorise; size
      // grows with the tier as a second encoding. Package-root-only and peripheral stay neutral grey,
      // because those are absence of evidence rather than a cooler tier.
      // Defensive: a flagged cell with no proximity entry at all (only if a license has no file evidence).
      if (p === null) [color, size] = ['var(--cavil-grey-2)', 0.48];
      else if (p.tier) [color, size] = ['var(--cavil-edge-7)', 0.48];
      else if (p.same_file) [color, size] = ['var(--cavil-heat-1)', 0.85];
      else if ((p.lca_depth ?? 0) >= 3) [color, size] = ['var(--cavil-heat-2)', 0.7];
      else if ((p.lca_depth ?? 0) >= 1) [color, size] = ['var(--cavil-heat-3)', 0.58];
      else [color, size] = ['var(--cavil-grey-2)', 0.48];
      // Confidence dims the dot: a real match is solid, a fold muted, an unresolved guess faint - so the
      // trustworthy co-locations read strongest even at the same proximity tier.
      const opacity = p ? ({3: 1, 2: 0.7, 1: 0.5}[p.confidence] ?? 1) : 0.5;
      return {background: color, height: `${size}rem`, width: `${size}rem`, opacity};
    },
    cell(outbound, inbound) {
      return this.matrix?.[outbound]?.[inbound] ?? null;
    },
    isMutual(outbound, inbound) {
      return (
        this.cell(outbound, inbound)?.compatibility === 'No' && this.cell(inbound, outbound)?.compatibility === 'No'
      );
    },
    // Which sides of a mutual (both-direction) tile touch another mutual tile. The CSS drops the rounded
    // corner and inter-cell gap on those sides so a run of conflicts merges into a single block, leaving
    // rounded corners only on the block's free edges.
    mutualCornerClass(i, j) {
      const rows = this.visibleLicenses;
      if (!this.isMutual(rows[i], rows[j])) return null;
      const touches = (a, b) =>
        a >= 0 && b >= 0 && a < rows.length && b < rows.length && this.isMutual(rows[a], rows[b]);
      return {
        'mut-up': touches(i - 1, j),
        'mut-down': touches(i + 1, j),
        'mut-left': touches(i, j - 1),
        'mut-right': touches(i, j + 1)
      };
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
      if (cell.compatibility === 'No') return '';
      return '';
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
    selectedAxisClass(axis, name) {
      if (this.selected === null || this.selected[axis] !== name) return null;
      return ['is-selected', this.verdictAxisClass(this.selected.compatibility)];
    },
    verdictAxisClass(compatibility) {
      if (compatibility === 'No') return 'axis-no';
      if (compatibility === 'Check dependency') return 'axis-check';
      return 'axis-unknown';
    },
    showMatrixTooltip(outbound, inbound, event) {
      const cell = this.cell(outbound, inbound);
      if (outbound === inbound || cell === null) {
        this.hovered = null;
        return;
      }
      this.hovered = {outbound, inbound, compatibility: cell.compatibility, ...this.tooltipPosition(event)};
    },
    moveMatrixTooltip(event) {
      if (this.hovered === null) return;
      this.hovered = {...this.hovered, ...this.tooltipPosition(event)};
    },
    hideMatrixTooltip() {
      this.hovered = null;
    },
    tooltipPosition(event) {
      const width = 240;
      const margin = 12;
      const x = Math.min(Math.max(event.clientX, margin + width / 2), window.innerWidth - margin - width / 2);
      const y = Math.max(event.clientY - 14, margin + 70);
      return {x, y};
    },
    selectCell(outbound, inbound) {
      const cell = this.cell(outbound, inbound);
      if (outbound === inbound || cell === null) {
        this.selected = null;
        return;
      }
      if (this.isActive(outbound, inbound)) {
        this.selected = null;
        return;
      }
      this.selected = {outbound, inbound, compatibility: cell.compatibility, explanation: cell.explanation};
    }
  }
};
</script>

<style scoped>
.license-matrix-card {
  border: 1px solid var(--cavil-border);
  border-radius: 6px;
  box-shadow: 0 1px 3px rgba(var(--cavil-shadow-rgb), 0.08);
  min-width: 0;
  overflow: hidden;
}
.license-matrix-header {
  align-items: center;
  background: var(--cavil-canvas-subtle);
  border-bottom: 1px solid var(--cavil-border);
  border-radius: 6px 6px 0 0;
  display: flex;
  gap: 1rem;
  justify-content: space-between;
  padding: 0.75rem 1rem;
}
.license-matrix-header h3 {
  font-size: 1rem;
  line-height: 1.3;
  margin: 0;
}
.license-matrix-body {
  background: var(--cavil-canvas);
  padding: 1rem;
}

/* Heatmap grid - GitHub contribution-graph aesthetic */
.license-matrix-grid-wrap {
  overflow-x: auto;
}
.license-matrix-tooltip {
  background: var(--cavil-inverse-bg);
  border-radius: 6px;
  box-shadow: 0 8px 24px rgba(var(--cavil-neutral-rgb), 0.22);
  color: var(--cavil-inverse-fg);
  display: grid;
  font-size: 12px;
  font-weight: 600;
  gap: 0.3rem;
  line-height: 1.35;
  max-width: 240px;
  overflow-wrap: anywhere;
  padding: 0.5rem 0.6rem;
  pointer-events: none;
  position: fixed;
  text-align: left;
  transform: translate(-50%, calc(-100% - 10px));
  width: max-content;
  z-index: 1060;
}
.license-matrix-tooltip::after {
  border: 6px solid transparent;
  border-top-color: var(--cavil-inverse-bg);
  content: '';
  left: 50%;
  position: absolute;
  top: 100%;
  transform: translateX(-50%);
}
.license-matrix-tooltip strong {
  font-size: 13px;
  letter-spacing: 0;
}
.license-matrix-tooltip-line {
  display: grid;
  gap: 0.4rem;
  grid-template-columns: minmax(3.1rem, auto) minmax(0, 1fr);
}
.license-matrix-tooltip-label {
  color: var(--cavil-inverse-fg-muted);
  font-weight: 700;
  white-space: nowrap;
}
.license-matrix-grid {
  border-collapse: separate;
  /* No gap between cells: the small floating dots keep their air from the cell being larger than the
     dot, while adjacent both-direction tiles (which fill the whole cell) merge into one block. */
  border-spacing: 0;
  font-size: 12px;
}
.license-matrix-corner {
  background: var(--cavil-canvas);
  left: 0;
  position: sticky;
  z-index: 2;
}
.license-matrix-colhead {
  color: var(--cavil-fg-subtle);
  font-size: 11px;
  font-variant-numeric: tabular-nums;
  font-weight: 600;
  min-width: 1.5rem;
  padding: 0.15rem 0.2rem;
  text-align: center;
  vertical-align: middle;
}
/* Active row/column: the axis numbers and the selected row name go bold black. We fake the weight with
   -webkit-text-stroke (a paint-time thickening) instead of font-weight, because a real weight change
   would widen the glyphs and could resize the sticky first column - shifting the whole grid on select.
   Stroke changes no metrics, so the matrix stays put. */
.license-matrix-colhead.is-selected,
.license-matrix-rowhead.is-selected .license-matrix-rowhead-index,
.license-matrix-rowhead.is-selected .license-matrix-rowhead-name {
  -webkit-text-stroke: 0.4px var(--cavil-fg);
  color: var(--cavil-fg);
}
.license-matrix-rowhead {
  background: var(--cavil-canvas);
  left: 0;
  padding: 0.15rem 0.85rem 0.15rem 0;
  position: sticky;
  text-align: left;
  vertical-align: middle;
  white-space: nowrap;
  z-index: 1;
}
.license-matrix-rowhead-index {
  color: var(--cavil-fg-subtle);
  display: inline-block;
  font-size: 11px;
  font-variant-numeric: tabular-nums;
  font-weight: 600;
  margin-right: 0.5rem;
  min-width: 1.1rem;
  text-align: right;
}
.license-matrix-rowhead-name {
  color: var(--cavil-fg);
  font-size: 12px;
  font-weight: 500;
}

.license-matrix-cell {
  border-radius: 4px;
  font-size: 0;
  height: 1.35rem;
  min-width: 1.6rem;
  position: relative;
  text-align: center;
  vertical-align: middle;
}
.license-matrix-mark {
  border-radius: 50%;
  display: inline-block;
  height: 0.7rem;
  position: relative;
  transition:
    transform 0.12s ease,
    box-shadow 0.12s ease;
  vertical-align: middle;
  width: 0.7rem;
}
/* Colour classes - shared by the grid cells and the legend swatches (colour only, no behaviour) */
.cell-self {
  background: var(--cavil-canvas-subtle);
}
.cell-yes {
  background: var(--cavil-tint-8);
}
.cell-no {
  background: var(--cavil-danger-bg);
  border-color: var(--cavil-danger-border);
  color: var(--cavil-danger);
  font-weight: 600;
}
.cell-check {
  background: var(--cavil-attention-bg);
  border-color: var(--cavil-edge-8);
  color: var(--cavil-attention-deep);
  font-weight: 600;
}
.cell-unknown {
  background: var(--cavil-neutral-bg);
  border-color: rgba(var(--cavil-neutral-alt-rgb), 0.25);
  color: var(--cavil-fg-muted);
}
/* In the grid the cell itself is a transparent tile; the colour lives in the dot (see below). The
   colour classes above are reused as-is by the legend swatches. */
.license-matrix-cell.cell-self,
.license-matrix-cell.cell-yes,
.license-matrix-cell.cell-no,
.license-matrix-cell.cell-check,
.license-matrix-cell.cell-unknown {
  background: transparent;
}
/* Compatible and self cells carry no mark at all - only problems get ink, so the grid stays calm. */

/* Both-directions "No": fill the tile behind the dot so the mutually-incompatible pairs (symmetric
   across the diagonal) read as connected blocks, distinct from one-directional dots. The fill is a calm
   neutral slate (not red) so it marks the region without doubling up on the red dots; the red dots stay
   the severity signal. */
.license-matrix-cell.cell-no.is-mutual {
  background: var(--cavil-tint-11);
  border-radius: 6px;
}
/* In Likelihood mode the "both directions" block is less relevant (proximity, not direction, is the point),
   so soften its fill to a barely-there tint that still groups the region without competing with the heat. */
.license-matrix-cell.mode-likelihood.cell-no.is-mutual {
  background: var(--cavil-tint-1);
}
/* Merge a run of adjacent mutual tiles into a single block: square off (and, via border-spacing:0,
   butt up against) every side that touches another mutual tile, so only the block's outer corners
   stay rounded. The mut-* classes are set from JS by looking at each tile's four neighbours. */
.license-matrix-cell.is-mutual.mut-up {
  border-top-left-radius: 0;
  border-top-right-radius: 0;
}
.license-matrix-cell.is-mutual.mut-down {
  border-bottom-left-radius: 0;
  border-bottom-right-radius: 0;
}
.license-matrix-cell.is-mutual.mut-left {
  border-top-left-radius: 0;
  border-bottom-left-radius: 0;
}
.license-matrix-cell.is-mutual.mut-right {
  border-top-right-radius: 0;
  border-bottom-right-radius: 0;
}
/* Solid, soft dots (no rings) - one calm mark per flagged relationship. */
.license-matrix-cell.cell-no .license-matrix-mark {
  background: var(--cavil-grey-3);
}
.license-matrix-cell.cell-check .license-matrix-mark {
  background: var(--cavil-grey-1);
}
.license-matrix-cell.cell-unknown .license-matrix-mark {
  background: var(--cavil-edge-6);
}

/* Only the grid cells are interactive; the legend swatches reuse the colour classes above */
.license-matrix-cell.cell-no,
.license-matrix-cell.cell-check,
.license-matrix-cell.cell-unknown {
  cursor: pointer;
}
.license-matrix-cell.cell-no:hover .license-matrix-mark,
.license-matrix-cell.cell-check:hover .license-matrix-mark,
.license-matrix-cell.cell-unknown:hover .license-matrix-mark {
  transform: scale(1.2);
}
/* Selected cell: the dot lifts (grows + soft shadow with a white halo) like a tapped calendar day. */
.license-matrix-cell.is-active .license-matrix-mark {
  box-shadow:
    0 0 0 2px var(--cavil-canvas),
    0 1px 3px rgba(var(--cavil-shadow-rgb), 0.28);
  transform: scale(1.3);
}

/* A quiet reference footer, parked below the explanation so it stays out of the matrix<->explanation
   eye path. Muted swatch + text, no chip chrome, so it recedes rather than competing for attention. */
.license-matrix-legend {
  align-items: center;
  border-top: 1px solid var(--cavil-neutral-bg);
  color: var(--cavil-fg-subtle);
  display: flex;
  flex-wrap: wrap;
  font-size: 11px;
  font-weight: 500;
  gap: 0.9rem;
  padding: 0.6rem 1rem;
}
.license-matrix-legend-item {
  align-items: center;
  display: inline-flex;
  gap: 0.35rem;
  white-space: nowrap;
}
.license-matrix-swatch {
  border-radius: 50%;
  display: inline-block;
  height: 0.7rem;
  width: 0.7rem;
}
/* Solid dots, matching the grid marks. */
.license-matrix-swatch.cell-no {
  background: var(--cavil-grey-3);
}
.license-matrix-swatch.cell-check {
  background: var(--cavil-grey-1);
}
.license-matrix-swatch.cell-unknown {
  background: var(--cavil-edge-6);
}
/* Compatible is drawn as empty space in the grid; show a faint outline here to say so. */
.license-matrix-swatch.cell-yes {
  background: var(--cavil-canvas);
  box-shadow: inset 0 0 0 1px var(--cavil-border);
}
/* Both-directions: the filled tile behind the dot. */
.license-matrix-swatch.swatch-mutual {
  background: var(--cavil-tint-11);
  border-radius: 3px;
}

/* White tile on the grey header bar, mirroring the composition chart's stat tile, so the control
   stands out from the bar instead of blending into it. The count is styled like that tile's value
   (big + bold) with a small muted unit word, rather than a parenthesised number. */
.license-matrix-toggle {
  align-items: baseline;
  appearance: none;
  background: var(--cavil-canvas);
  border: 1px solid var(--cavil-border);
  border-radius: 6px;
  color: var(--cavil-fg);
  cursor: pointer;
  display: inline-flex;
  font: inherit;
  font-size: 12px;
  font-weight: 500;
  gap: 0.3rem;
  line-height: 1.2;
  padding: 0.25rem 0.55rem;
}
.license-matrix-toggle:hover {
  background: var(--cavil-canvas-subtle);
}
.license-matrix-toggle-count {
  color: var(--cavil-fg-emphasis);
  font-size: 1rem;
  font-variant-numeric: tabular-nums;
  font-weight: 700;
  line-height: 1;
}
.license-matrix-toggle-unit {
  color: var(--cavil-fg-muted);
  font-size: 12px;
  font-weight: 600;
}

.license-matrix-detail {
  border-top: 1px solid var(--cavil-border);
}

/* A deliberate two-band element: a verdict-tinted title bar over the explanation body. The bar's
   colour matches the cell that was clicked, tying the panel to the grid. */
.license-matrix-detail-bar {
  align-items: center;
  border-bottom: 1px solid var(--cavil-border);
  color: var(--cavil-fg);
  display: flex;
  flex-wrap: wrap;
  font-size: 12px;
  gap: 0.4rem;
  justify-content: space-between;
  padding: 0.55rem 1rem;
}
.bar-no {
  background: var(--cavil-tint-9);
  border-bottom-color: var(--cavil-edge-5);
}
.bar-check {
  background: var(--cavil-tint-7);
  border-bottom-color: var(--cavil-edge-4);
}
.bar-unknown {
  background: var(--cavil-tint-6);
  border-bottom-color: var(--cavil-edge-3);
}
.license-matrix-verdict {
  color: var(--cavil-fg);
  font-weight: 700;
}
.license-matrix-detail-title {
  align-items: center;
  display: inline-flex;
  flex-wrap: wrap;
  gap: 0.4rem;
}
.license-matrix-detail-label {
  color: var(--cavil-fg-muted);
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.02em;
  margin-left: auto;
  text-transform: uppercase;
}
.license-matrix-connector {
  color: var(--cavil-fg-muted);
}
.license-matrix-detail-name {
  color: var(--cavil-fg);
  font-weight: 600;
}
.license-matrix-detail-body {
  background: var(--cavil-canvas);
  color: var(--cavil-fg);
  font-size: 13px;
  line-height: 1.5;
  margin: 0;
  padding: 0.85rem 1rem;
}
.bar-no + .license-matrix-detail-body {
  box-shadow: inset 0 11px 17px -20px rgba(var(--cavil-shadow-cool-rgb), 0.55);
}
.bar-check + .license-matrix-detail-body {
  box-shadow: inset 0 11px 17px -20px rgba(var(--cavil-neutral-soft-rgb), 0.5);
}
.bar-unknown + .license-matrix-detail-body {
  box-shadow: inset 0 11px 17px -20px rgba(var(--cavil-neutral-pale-rgb), 0.5);
}

/* Header controls: the colour-mode switch sits next to the show-all toggle. */
.license-matrix-controls {
  align-items: center;
  display: flex;
  gap: 0.6rem;
}
.license-matrix-mode {
  background: var(--cavil-canvas);
  border: 1px solid var(--cavil-border);
  border-radius: 6px;
  display: inline-flex;
  overflow: hidden;
}
.license-matrix-mode-btn {
  appearance: none;
  background: var(--cavil-canvas);
  border: 0;
  color: var(--cavil-fg-muted);
  cursor: pointer;
  font: inherit;
  font-size: 12px;
  font-weight: 600;
  line-height: 1.2;
  padding: 0.25rem 0.6rem;
}
.license-matrix-mode-btn + .license-matrix-mode-btn {
  border-left: 1px solid var(--cavil-border);
}
.license-matrix-mode-btn:hover {
  background: var(--cavil-canvas-subtle);
}
.license-matrix-mode-btn.is-on {
  background: var(--cavil-accent-emphasis);
  color: var(--cavil-on-accent);
}

/* Detail panel "Where" band: proximity summary + file-browser links, parked under the OSADL explanation. */
.license-matrix-where {
  border-top: 1px solid var(--cavil-neutral-bg);
  display: flex;
  flex-direction: column;
  gap: 0.4rem;
  padding: 0.6rem 1rem;
}
.license-matrix-where-head {
  align-items: center;
  display: inline-flex;
  flex-wrap: wrap;
  gap: 0.5rem;
}
.license-matrix-where-label {
  color: var(--cavil-fg-muted);
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.02em;
  text-transform: uppercase;
}
.license-matrix-where-verdict {
  color: var(--cavil-fg);
  font-size: 13px;
  font-weight: 600;
}
.license-matrix-where-tag {
  background: var(--cavil-tint-5);
  border-radius: 999px;
  color: var(--cavil-fg-muted);
  font-size: 11px;
  font-weight: 600;
  padding: 0.05rem 0.5rem;
}
/* Files stacked one per line on a dotted rail, matching the license list's file lists (.risk-file-list in
   ReportDetails): a muted link with a small ::before dot, blue + underline only on hover. */
.license-matrix-file-list {
  border-left: 1px solid var(--cavil-border);
  color: var(--cavil-fg-muted);
  font-size: 13px;
  list-style: none;
  margin: 0.1rem 0 0 0.35rem;
  padding-left: 0.9rem;
}
.license-matrix-file-list li {
  align-items: center;
  display: grid;
  gap: 0.55rem;
  grid-template-columns: auto minmax(0, 1fr);
  line-height: 1.35;
  position: relative;
}
.license-matrix-file-list li::before {
  background: var(--cavil-fg-subtle);
  border: 2px solid var(--cavil-canvas);
  border-radius: 50%;
  box-shadow: 0 0 0 1px var(--cavil-border);
  content: '';
  height: 0.45rem;
  margin-left: -1.15rem;
  width: 0.45rem;
}
.license-matrix-file-list li + li {
  margin-top: 0.35rem;
}
.license-matrix-file-link {
  color: var(--cavil-fg-muted);
  overflow-wrap: anywhere;
  text-decoration-color: transparent;
}
.license-matrix-file-link:hover,
.license-matrix-file-link:focus {
  color: var(--cavil-accent-strong);
  text-decoration-color: currentColor;
}

/* Likelihood legend swatches: distinct hues down the heat scale, a grey for peripheral - matching
   markStyle so the grid and the key read as one scale. */
.license-matrix-swatch.swatch-file {
  background: var(--cavil-heat-1);
}
.license-matrix-swatch.swatch-deep {
  background: var(--cavil-heat-2);
}
.license-matrix-swatch.swatch-shared {
  background: var(--cavil-heat-3);
}
.license-matrix-swatch.swatch-root {
  background: var(--cavil-grey-2);
}
.license-matrix-swatch.swatch-peripheral {
  background: var(--cavil-edge-7);
}
</style>
