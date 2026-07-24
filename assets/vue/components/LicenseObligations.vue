<template>
  <div class="license-obligations" :class="{'is-open': open}">
    <button
      type="button"
      class="license-obligations-toggle"
      :aria-expanded="open ? 'true' : 'false'"
      @click="open = !open"
    >
      <i :class="['fa-solid', open ? 'fa-caret-down' : 'fa-caret-right']" aria-hidden="true"></i>
      Obligations
    </button>

    <div v-if="open" class="license-obligations-body">
      <span class="lob-source">OSADL</span>
      <section v-for="lic in licenses" :key="lic.license" class="lob-license">
        <h5 v-if="showNames" class="lob-license-name">
          <a class="spdx-link" :href="lic.spdxUrl" target="_blank" rel="noopener noreferrer">{{ lic.license }}</a>
        </h5>

        <dl v-if="lic.attrs.length > 0" class="lob-attrs">
          <div v-for="attr in lic.attrs" :key="attr.label" class="lob-attr">
            <dt>{{ attr.label }}</dt>
            <dd>{{ attr.value }}</dd>
          </div>
        </dl>

        <div v-for="uc in lic.sections" :key="uc.label" class="lob-usecase">
          <div class="lob-usecase-label">{{ uc.label }}</div>
          <ul v-if="uc.rows.length > 0" class="lob-tree">
            <li
              v-for="(row, idx) in uc.rows"
              :key="idx"
              :class="['lob-row', 'lob-' + row.kind]"
              :style="{paddingLeft: row.depth * 1.15 + 'rem'}"
            >
              <i v-if="row.icon" :class="['lob-icon', 'fa-solid', row.icon]" aria-hidden="true"></i>
              <span v-if="row.label" class="visually-hidden">{{ row.label }}</span>
              <span class="lob-text">{{ row.text }}</span>
            </li>
          </ul>
          <p v-else class="lob-none">No specific obligations.</p>
        </div>

        <p v-if="lic.sections.length === 0" class="lob-none">No obligation checklist published for this license.</p>
      </section>
    </div>
  </div>
</template>

<script>
import {spdxLicenseUrl} from '../helpers/links.js';

// Structural keywords in OSADL's obligation trees. "IF" variants introduce a condition; everything not
// listed here (or below) is a named obligation/qualifier rendered verbatim.
const CONDITIONS = {
  IF: 'If',
  'EXCEPT IF': 'Except if',
  'EITHER IF': 'If any of',
  'OR IF': 'Or if'
};

// Row kind -> Font Awesome icon. Obligations get a check / cross by SHAPE (must vs must not); conditions
// and alternatives get a branch. Kinds without an entry (attribute, group, text) render without an icon.
const ICONS = {
  must: 'fa-check',
  mustnot: 'fa-xmark',
  condition: 'fa-diamond',
  alt: 'fa-circle'
};

// Screen-reader labels so the must / must-not meaning does not rely on the (aria-hidden) icon alone.
const LABELS = {must: 'Must', mustnot: 'Must not'};

function isEmpty(value) {
  if (value === null || value === undefined) return true;
  if (Array.isArray(value)) return value.length === 0;
  if (typeof value === 'object') return Object.keys(value).length === 0;
  return false;
}

export default {
  name: 'LicenseObligations',
  props: {
    // One entry per constituent SPDX identifier (an expression like "MIT OR BSD-3-Clause" yields two),
    // each: {license, patent_hints?, copyleft?, source_disclosure?, use_cases?}. OSADL data, verbatim.
    entries: {type: Array, default: () => []},
    // The license-list label this panel belongs to (may be an expression). Drives whether to name each
    // constituent: redundant for a plain single license, but needed when the label is an expression -
    // especially when only some constituents are OSADL-known (e.g. "BSD-2-Clause AND AOMPL-1.0", where
    // AOMPL-1.0 has no checklist), so the obligations shown are clearly attributed to BSD-2-Clause.
    label: {type: String, default: ''}
  },
  data() {
    return {open: false};
  },
  computed: {
    // Show per-constituent names for expressions (more than one entry, or a single entry whose license
    // differs from the row label - i.e. an expression with one OSADL-known part); hide the redundant
    // name for a plain single license.
    showNames() {
      if (this.entries.length > 1) return true;
      if (this.entries.length === 1) return this.label !== '' && this.entries[0].license !== this.label;
      return false;
    },
    // Everything the template needs, derived once. A computed is cached, so the recursive tree walk runs
    // a single time per data change instead of on every poll-driven re-render of the parent report.
    licenses() {
      return this.entries.map(entry => ({
        license: entry.license,
        spdxUrl: spdxLicenseUrl(entry.license),
        attrs: this.attributes(entry),
        sections: this.useCaseSections(entry)
      }));
    }
  },
  methods: {
    // The verified classification facts OSADL carries for a license, kept inside the panel (not leaked to
    // the row's flag chips). Only shown when present.
    attributes(entry) {
      const attrs = [];
      if (entry.copyleft) attrs.push({label: 'Copyleft', value: entry.copyleft});
      if (entry.source_disclosure) attrs.push({label: 'Source disclosure', value: entry.source_disclosure});
      if (entry.patent_hints) attrs.push({label: 'Patent hints', value: entry.patent_hints});
      return attrs;
    },
    // One section per OSADL "use case" (delivery scenario). The value is normally a nested obligation
    // tree, but for obligation-free licenses (0BSD, MIT-0, ...) OSADL gives the use case as a bare string
    // label with no obligations - then rows is empty and we say so.
    useCaseSections(entry) {
      const useCases = entry.use_cases;
      if (!useCases) return [];
      if (typeof useCases === 'string') return [{label: useCases, rows: []}];
      return Object.keys(useCases).map(label => ({label, rows: this.flatten(useCases[label], 0)}));
    },
    addRow(out, depth, kind, text) {
      out.push({depth, kind, text, icon: ICONS[kind], label: LABELS[kind]});
    },
    // Flatten OSADL's recursive obligation tree into depth-annotated rows so it renders as one calm,
    // indented outline. Kinds drive the styling: obligations (must/mustnot), conditions and alternatives
    // (branch), named sub-groups, and leaf qualifiers (attribute). Rendered verbatim; nothing is dropped.
    flatten(node, depth, out) {
      out = out || [];
      if (node === null || node === undefined) return out;
      if (typeof node === 'string') {
        this.addRow(out, depth, 'text', node);
        return out;
      }
      if (Array.isArray(node)) {
        for (const item of node) this.flatten(item, depth, out);
        return out;
      }

      for (const [key, value] of Object.entries(node)) {
        if (key === 'YOU MUST') {
          this.emitObligation(value, depth, out, 'must');
        } else if (key === 'YOU MUST NOT') {
          this.emitObligation(value, depth, out, 'mustnot');
        } else if (key === 'ATTRIBUTE') {
          for (const attr of Array.isArray(value) ? value : [value]) this.addRow(out, depth, 'attribute', attr);
        } else if (CONDITIONS[key]) {
          for (const [condition, subtree] of Object.entries(value || {})) {
            this.addRow(out, depth, 'condition', `${CONDITIONS[key]} ${condition}`);
            this.flatten(subtree, depth + 1, out);
          }
        } else if (key === 'EITHER') {
          this.addRow(out, depth, 'alt', 'Satisfy any one of:');
          this.flatten(value, depth + 1, out);
        } else if (key === 'OR' || /^\d+$/u.test(key)) {
          // Alternative branches and numbered branch containers add no line of their own.
          this.flatten(value, depth, out);
        } else {
          this.emitNamed(key, value, depth, out);
        }
      }
      return out;
    },
    // A "YOU MUST"/"YOU MUST NOT" value is a string, an array of strings, or a {name: subtree} object.
    emitObligation(value, depth, out, kind) {
      if (typeof value === 'string') {
        this.addRow(out, depth, kind, value);
      } else if (Array.isArray(value)) {
        for (const item of value) this.addRow(out, depth, kind, item);
      } else if (value && typeof value === 'object') {
        for (const [name, subtree] of Object.entries(value)) {
          this.addRow(out, depth, kind, name);
          this.flatten(subtree, depth + 1, out);
        }
      }
    },
    // A named node that is not a keyword. With children it is a labelled sub-group; when empty it is a
    // leaf qualifier - OSADL encodes some qualifiers (e.g. "Duration At least 3 years") as empty-valued
    // keys, which would otherwise render as bare, dangling headers.
    emitNamed(key, value, depth, out) {
      if (isEmpty(value)) {
        this.addRow(out, depth, 'attribute', key);
        return;
      }
      this.addRow(out, depth, 'group', key);
      this.flatten(value, depth + 1, out);
    }
  }
};
</script>

<style scoped>
.license-obligations {
  margin-top: 0.4rem;
}

/* Quiet, in-row toggle - the license list stays as clean as before until a reviewer opens it. */
.license-obligations-toggle {
  align-items: center;
  appearance: none;
  background: transparent;
  border: 0;
  color: #57606a;
  cursor: pointer;
  display: inline-flex;
  font: inherit;
  font-size: 12px;
  font-weight: 600;
  gap: 0.4rem;
  letter-spacing: 0.01em;
  padding: 0.1rem 0;
}
/* :focus-visible, not :focus, so a mouse click does not leave the toggle stuck blue after it keeps
   focus - keyboard users still get the colour cue. */
.license-obligations-toggle:hover,
.license-obligations-toggle:focus-visible {
  color: #0969da;
}
.license-obligations-toggle i {
  color: #8c959f;
  width: 0.7rem;
}

/* A full-width section of the license row, not a card floating inside it: negative horizontal margins
   cancel the .risk-license-item padding so the top rule spans edge to edge, and content re-pads to stay
   aligned with the license name above. */
.license-obligations-body {
  border-top: 1px solid #d8dee4;
  margin: 0.5rem -1rem 0;
  position: relative;
}
.lob-license {
  border-top: 1px solid #eaeef2;
  padding: 0.7rem 1rem;
}
.lob-license:first-child {
  border-top: 0;
}
.lob-license-name {
  font-size: 13px;
  font-weight: 600;
  margin: 0 0 0.5rem;
}
.lob-license-name .spdx-link {
  color: #1f2328;
}

/* Verified classification facts, "low tech report" style: small-caps muted label + plain value. */
.lob-attrs {
  display: flex;
  flex-wrap: wrap;
  gap: 0.3rem 1.4rem;
  margin: 0 0 0.7rem;
}
.lob-attr {
  align-items: baseline;
  display: inline-flex;
  gap: 0.4rem;
}
.lob-attr dt {
  color: #6e7781;
  font-size: 10px;
  font-weight: 600;
  letter-spacing: 0.04em;
  text-transform: uppercase;
}
.lob-attr dd {
  color: #1f2328;
  font-size: 12px;
  font-weight: 500;
  margin: 0;
}

.lob-usecase {
  margin-top: 0.65rem;
}
.lob-usecase:first-of-type {
  margin-top: 0;
}
.lob-usecase-label {
  color: #57606a;
  font-size: 10px;
  font-weight: 700;
  letter-spacing: 0.05em;
  margin-bottom: 0.3rem;
  text-transform: uppercase;
}

/* One indented outline per use case; nesting is carried by indentation and the row icons. */
.lob-tree {
  list-style: none;
  margin: 0;
  padding: 0;
}
.lob-row {
  align-items: baseline;
  color: #1f2328;
  display: flex;
  font-size: 13px;
  gap: 0.45rem;
  line-height: 1.45;
  padding-bottom: 0.15rem;
  padding-top: 0.15rem;
}
.lob-icon {
  flex: 0 0 auto;
  font-size: 11px;
  text-align: center;
  width: 0.95rem;
}
.lob-text {
  overflow-wrap: anywhere;
}

/* Obligations: distinguished by icon SHAPE (check vs cross), with only a muted tint - deep reds are
   reserved for risk signals elsewhere, so must-not uses a calm terracotta rather than a signal red. */
.lob-must .lob-icon {
  color: #57606a;
}
.lob-mustnot .lob-icon {
  color: #a0562d;
}

/* Conditions and alternatives read as group headers, not code: muted branch icon, semibold (not italic)
   text, a little breathing room above so they introduce the obligations beneath them. */
.lob-condition,
.lob-alt,
.lob-group {
  margin-top: 0.3rem;
}
.lob-condition .lob-icon,
.lob-alt .lob-icon {
  color: #8c959f;
}
.lob-condition .lob-text,
.lob-alt .lob-text,
.lob-group .lob-text {
  color: #57606a;
  font-weight: 600;
}

/* Leaf qualifiers: quiet, dash-led, so the "how" recedes behind the obligation itself. */
.lob-attribute .lob-text {
  color: #6e7781;
  font-size: 12px;
}
/* Leaf qualifiers and named sub-group headers share one dash marker so every item at a level is
   marked consistently; weight (group is semibold, qualifier muted) carries the hierarchy. */
.lob-attribute .lob-text::before,
.lob-group .lob-text::before {
  color: #8c959f;
  content: '– ';
}

.lob-none {
  color: #6e7781;
  font-size: 12px;
  font-style: italic;
  margin: 0;
}

/* Source credit floated top-right, mirroring the "OSADL verdict" label on the compatibility matrix.
   Absolute so it does not take its own line; room for other sources beside OSADL later. */
.lob-source {
  color: #57606a;
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.02em;
  position: absolute;
  right: 1rem;
  text-transform: uppercase;
  top: 0.5rem;
}
</style>
