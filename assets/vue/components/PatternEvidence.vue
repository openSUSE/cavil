<template>
  <div class="pattern-evidence">
    <div class="evidence-section">
      <div class="evidence-label">
        Matched text
        <span class="evidence-note">{{ alignmentSummary }}</span>
      </div>
      <div class="evidence-text">
        <template v-for="(segment, i) in segments" :key="i">
          <span v-if="segment.skip !== undefined" class="evidence-skip" :title="`$SKIP${segment.skip}`">{{
            segment.words
          }}</span>
          <span v-else>{{ segment.text }}</span>
        </template>
      </div>
    </div>
    <div class="evidence-section evidence-precedent">
      <div class="evidence-label">
        Precedent
        <span class="evidence-note">{{ precedentSummary }}</span>
      </div>
      <table v-if="precedent.rows.length > 0" class="table table-sm evidence-table">
        <tbody>
          <tr v-for="row in precedent.rows" :key="row.id" :class="agrees(row) ? 'evidence-agree' : 'evidence-differ'">
            <td>
              <a :href="`/licenses/edit_pattern/${row.id}`" target="_blank">#{{ row.id }}</a>
            </td>
            <td>{{ row.license }}</td>
            <td>risk {{ row.risk }}</td>
            <td>{{ row.contained ? 'matches inside this text' : `${percent(row.text_cov)} shared wording` }}</td>
          </tr>
        </tbody>
      </table>
    </div>
    <div class="evidence-section evidence-impact">
      <div class="evidence-label">
        Impact
        <span class="evidence-note">{{ impactSummary }}</span>
      </div>
      <ul v-if="impact.samples && impact.samples.length > 0" class="evidence-samples">
        <li v-for="sample in impact.samples" :key="sample.snippet">
          <a :href="`/reviews/details/${sample.package}`" target="_blank">{{ sample.name }}</a>
          {{ sample.filename }}:{{ sample.sline }} · {{ sample.resolution ?? 'unresolved' }}
        </li>
      </ul>
    </div>
  </div>
</template>

<script>
// Server-computed facts of a pattern proposal (see _pattern_evidence in the MCP plugin), so a reviewer checks
// what the pattern swallows, which curated patterns agree and how far it reaches without reading $SKIP tokens
export default {
  name: 'PatternEvidence',
  props: {data: {type: Object, required: true}},
  computed: {
    evidence() {
      return this.data.evidence;
    },
    segments() {
      const parts = this.data.pattern.split(/\$SKIP(\d+)/);
      const skips = this.evidence.alignment?.skips ?? [];
      const segments = [];
      for (let i = 0; i < parts.length; i++) {
        if (i % 2 === 0) segments.push({text: parts[i]});
        else segments.push({skip: parts[i], words: skips[(i - 1) / 2]?.words ?? `$SKIP${parts[i]}`});
      }
      return segments;
    },
    alignmentSummary() {
      const skips = this.evidence.alignment?.skips ?? [];
      if (skips.length === 0) return 'verbatim, nothing skipped';
      return `verbatim except ${skips.length} skipped span${skips.length === 1 ? '' : 's'} (greyed)`;
    },
    precedent() {
      return {rows: [], ...this.evidence.precedent};
    },
    precedentSummary() {
      const verdict = this.precedent.verdict;
      if (!verdict || verdict.status === 'none') return 'no curated pattern matches or resembles this wording';
      const classes = verdict.classes.map(c => `${c.license} risk ${c.risk}`).join(' vs. ');
      if (verdict.status === 'conflict') return `conflict: curated patterns disagree (${classes})`;
      return this.agrees(verdict.classes[0]) ? `follows ${classes}` : `curated patterns say ${classes}`;
    },
    impact() {
      return this.evidence.impact ?? {};
    },
    impactSummary() {
      const i = this.impact;
      if (i.error) return i.error;
      const plus = i.capped ? '+' : '';
      return `matches ${i.snippets}${plus} snippets in ${i.packages} package${i.packages === 1 ? '' : 's'}`;
    }
  },
  methods: {
    agrees(row) {
      return row.license === this.data.license && String(row.risk) === String(this.data.risk);
    },
    percent(value) {
      return `${Math.round((value ?? 0) * 100)}%`;
    }
  }
};
</script>

<style scoped>
.pattern-evidence {
  background: var(--cavil-canvas);
  font-size: 13px;
  line-height: 20px;
}
.evidence-section {
  padding: 10px;
}
.evidence-section + .evidence-section {
  border-top: 1px solid var(--cavil-border-faint);
}
.evidence-label {
  font-weight: 600;
  margin-bottom: 4px;
}
.evidence-note {
  color: var(--cavil-fg-muted);
  font-weight: normal;
  margin-left: 0.5rem;
}
.evidence-text {
  font-family: monospace;
  font-size: 12px;
  white-space: pre-wrap;
  word-break: break-word;
}
.evidence-skip {
  background: rgba(var(--cavil-neutral-cool-rgb), 0.2);
  border-radius: 3px;
  color: var(--cavil-fg-muted);
  font-style: italic;
  padding: 0 2px;
}
.evidence-table {
  margin: 0;
  width: auto;
}
.evidence-agree td:first-child {
  box-shadow: inset 3px 0 0 var(--cavil-success-emphasis);
}
.evidence-differ td:first-child {
  box-shadow: inset 3px 0 0 var(--cavil-danger);
}
.evidence-samples {
  margin: 0;
  padding-left: 18px;
}
</style>
