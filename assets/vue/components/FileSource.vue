<template>
  <table class="snippet" :class="{'editor-open': inlineEditor}">
    <colgroup>
      <col v-if="!readOnly" class="snippet-col-actions" />
      <col class="snippet-col-linenumber" />
      <col class="snippet-col-code" />
      <col v-if="!readOnly" class="snippet-col-quick-actions" />
    </colgroup>
    <tbody>
      <!-- eslint-disable-next-line vue/no-v-for-template-key -->
      <template v-for="(line, idx) in lines" :key="idx">
        <tr v-if="line[1].withgap">
          <td class="redbar" :colspan="readOnly ? 2 : 4"></td>
        </tr>
        <tr
          v-if="!isHiddenByEditor(line)"
          :id="matchStartId(line)"
          :class="rowClass(line[1])"
          @mouseenter="onRowEnter($event, line[1])"
          @mouseleave="onRowLeave"
        >
          <td v-if="!readOnly && !showActions(line[1])" class="actions"></td>
          <td v-else-if="!readOnly" class="actions dropdown show">
            <a
              href="#"
              :id="'dropdownMenuLink-' + fileId + '-' + line[0]"
              class="snippet-tool-btn"
              data-bs-toggle="dropdown"
              aria-haspopup="true"
              aria-expanded="false"
              title="Open action menu"
              aria-label="Open action menu"
            >
              <i class="actions-menu fa-solid fa-ellipsis-vertical"></i>
            </a>
            <div class="dropdown-menu" :aria-labelledby="'dropdownMenuLink-' + fileId + '-' + line[0]">
              <!-- Any snippet-backed line (unresolved, folded, or cleared) edits the snippet to
                   create or correct a pattern; a folded/cleared line is how a reviewer fixes a wrong
                   derived resolution. -->
              <a
                v-if="line[1].snippet"
                class="dropdown-item"
                :href="editSnippetUrl(line[1].snippet, line[1].hash)"
                @click="onCreateClick($event, line, line[1].snippet)"
                >{{ snippetActionLabel(line[1]) }}</a
              >
              <a
                v-else-if="line[1].risk === 9"
                class="dropdown-item"
                :href="newSnippetUrl(line[0], line[1].end, line[1].hash)"
                @click="onCreateClick($event, line, null)"
                >Create Pattern from selection</a
              >
              <a
                v-if="line[1].pid != null"
                class="dropdown-item"
                :href="editPatternUrl(line[1].pid)"
                target="_blank"
                rel="noopener"
                >Show Pattern</a
              >

              <template v-if="line[0] > 1">
                <div class="dropdown-divider"></div>
                <a
                  v-if="line[1].prevstart"
                  href="#"
                  class="dropdown-item"
                  @click.prevent="emitExtend('match-above', line)"
                  >Extend to match above</a
                >
                <a href="#" class="dropdown-item" @click.prevent="emitExtend('one-line-above', line)"
                  >Extend one line above</a
                >
                <a href="#" class="dropdown-item" @click.prevent="emitExtend('top', line)">Extend to the top of file</a>
              </template>

              <template v-if="line[1].end">
                <div class="dropdown-divider"></div>
                <a
                  v-if="line[1].nextend"
                  href="#"
                  class="dropdown-item"
                  @click.prevent="emitExtend('match-below', line)"
                  >Extend to match below</a
                >
                <a href="#" class="dropdown-item" @click.prevent="emitExtend('one-line-below', line)"
                  >Extend one line below</a
                >
                <a href="#" class="dropdown-item" @click.prevent="emitExtend('bottom', line)"
                  >Extend to the end of the file</a
                >
              </template>

              <div class="dropdown-divider"></div>
              <a href="#" class="dropdown-item" @click.prevent="emitExtend('reset', line)">Reset selection</a>
            </div>
          </td>

          <td class="linenumber">{{ line[0] }}</td>
          <td class="code">
            {{ line[2]
            }}<PendingActionIndicator
              v-for="action in actionsForLine(line)"
              :key="action.id"
              :action="action"
              @dismiss="onDismiss"
            />
            <a
              v-if="canExtendUp(line)"
              :id="`extend-up-${fileId}-${line[0]}`"
              href="#"
              class="snippet-tool-btn extend-vert-btn extend-up-btn"
              :title="`Extend one line above (line ${line[0] - 1})`"
              aria-label="Extend one line above"
              @click.prevent="onExtendUp($event, line)"
            >
              <i class="fa-solid fa-caret-up"></i>
            </a>
            <a
              v-if="canExtendDown(line)"
              :id="`extend-down-${fileId}-${line[0]}`"
              href="#"
              class="snippet-tool-btn extend-vert-btn extend-down-btn"
              :title="`Extend one line below (line ${line[0] + 1})`"
              aria-label="Extend one line below"
              @click.prevent="onExtendDown($event, line[0])"
            >
              <i class="fa-solid fa-caret-down"></i>
            </a>
            <a
              v-if="canCorrect(line)"
              :id="`correct-${fileId}-${line[0]}`"
              :href="editSnippetUrl(line[1].snippet, line[1].hash)"
              class="snippet-tool-btn correct-btn"
              :title="snippetActionLabel(line[1])"
              :aria-label="snippetActionLabel(line[1])"
            >
              <i class="fa-solid fa-pen-to-square"></i>
            </a>
          </td>

          <td v-if="!readOnly && line[1].end && line[1].risk === 9" class="quick-actions">
            <a
              :href="newSnippetUrl(line[0], line[1].end, line[1].hash)"
              class="snippet-tool-btn"
              target="_blank"
              title="Create pattern from selection"
              aria-label="Create pattern from selection"
              @click="onCreateClick($event, line, line[1].snippet || null)"
            >
              <i class="fa-solid fa-pen-to-square"></i>
            </a>
          </td>
          <td v-else-if="!readOnly" class="quick-actions"></td>
        </tr>
        <tr v-if="!readOnly && inlineEditor && inlineEditor.startLine === line[0]" class="inline-editor-row">
          <td colspan="4">
            <div id="inline-snippet-editor">
              <SnippetEditor
                :key="inlineEditor.key"
                :snippet-id="inlineEditor.snippetId"
                :hash="inlineEditor.hash"
                :from="inlineEditor.from"
                :initial="inlineEditor.initial"
                :has-contributor-role="hasContributorRole"
                :has-admin-role="hasAdminRole"
                mode="inline"
                @submit="$emit('editor-submit', $event)"
                @cancel="$emit('close-editor')"
              />
            </div>
          </td>
        </tr>
      </template>
    </tbody>
  </table>
</template>

<script>
import PendingActionIndicator from './PendingActionIndicator.vue';
import SnippetEditor from './SnippetEditor.vue';
import {patternIdsFromInfo, showPatternTooltip} from '../helpers/patternTooltip.js';

export default {
  name: 'FileSource',
  components: {PendingActionIndicator, SnippetEditor},
  props: {
    lines: {type: Array, required: true},
    fileId: {type: Number, required: true},
    filename: {type: String, default: ''},
    packname: {type: String, default: ''},
    hasAdminRole: {type: Boolean, default: false},
    hasContributorRole: {type: Boolean, default: false},
    pendingActions: {type: Array, default: () => []},
    inlineEditor: {type: Object, default: null},
    readOnly: {type: Boolean, default: false},
    // Link mode (used by the file browser): instead of the report's inline editor + extend
    // orchestration, snippet-backed regions (folded / cleared / unresolved) get a single button that
    // navigates to the full-page snippet editor. Keeps the file browser otherwise read-only.
    linkEditor: {type: Boolean, default: false}
  },
  emits: ['extend', 'open-editor', 'dismiss-action', 'close-editor', 'editor-submit'],
  data() {
    return {hoveredGroup: null, patternTooltip: null, pendingCompensation: null};
  },
  computed: {
    isAdminOrContributor() {
      return this.hasAdminRole || this.hasContributorRole;
    },
    matchExtents() {
      // Map keyed by match-end line number → metadata from the match-start
      // row. Lets the ▼ button on the match-end row identify which match to
      // extend and pass the original boundaries through to onExtend.
      const map = new Map();
      for (const line of this.lines) {
        const info = line[1];
        if (info.risk === 9 && info.end) {
          map.set(info.end, {
            startLine: line[0],
            endLine: info.end,
            prevstart: info.prevstart || 0,
            nextend: info.nextend || 0
          });
        }
      }
      return map;
    }
  },
  watch: {
    lines() {
      if (!this.pendingCompensation) return;
      const {kind, targetLine, beforeTop} = this.pendingCompensation;
      this.pendingCompensation = null;
      this.$nextTick(() => {
        const id =
          kind === 'one-line-above'
            ? `extend-up-${this.fileId}-${targetLine}`
            : `extend-down-${this.fileId}-${targetLine}`;
        // Re-align every frame until the button sits back under the cursor and
        // stays there. A single deferred measurement is fragile: on a loaded
        // machine the freshly inserted/removed rows can still be mid-reflow,
        // and measuring then yields a wildly wrong delta that hurls the page
        // hundreds of px away. Correcting each frame instead means the first
        // pass (off the synchronous getBoundingClientRect layout flush) absorbs
        // the bulk of the shift immediately, and any residual from a late
        // reflow (web-font / row-height settling) is mopped up on following
        // frames. Stop once aligned, capped so it can never spin forever.
        let frames = 0;
        const align = () => {
          const btn = document.getElementById(id);
          if (!btn) return;
          const delta = btn.getBoundingClientRect().top - beforeTop;
          if (Math.abs(delta) > 0.5) window.scrollBy(0, delta);
          else if (frames > 0) return;
          if (++frames <= 10) requestAnimationFrame(align);
        };
        align();
      });
    }
  },
  beforeUnmount() {
    if (this.patternTooltip) this.patternTooltip.destroy();
  },
  methods: {
    rowClass(info) {
      // Only tag rows that actually correspond to a match (license pattern
      // or unresolved snippet). The server hands back `risk: 0` for plain
      // context lines too — coloring those would paint the entire snippet
      // preview, defeating the highlight.
      const classes = [];
      if (info.pid != null || info.snippet != null) classes.push(`risk-${info.risk}`);
      if (info.hash) classes.push(`hash-${info.hash}`);
      // Derived resolutions (similarity-folded license / cleared boilerplate) are dashed so they
      // never look identical to a curated pattern match.
      if (info.folded) classes.push('folded');
      if (info.cleared) classes.push('cleared');
      if (patternIdsFromInfo(info).length > 0) classes.push('has-pattern-tooltip');
      // The first line of an unresolved snippet has both risk 9 and the `end`
      // marker added by Cavil::Util::lines_context. Keyboard navigation walks
      // these in document order.
      if (info.risk === 9 && info.end) classes.push('match-start');
      const group = this.groupKey(info);
      if (group !== null && group === this.hoveredGroup) classes.push('group-hovered');
      return classes;
    },
    groupKey(info) {
      // Matches a row of a license pattern (pid) or unresolved snippet
      // (snippet) so hovering anywhere in the block reveals its buttons.
      if (info.pid != null) return `p${info.pid}`;
      if (info.snippet != null) return `s${info.snippet}`;
      return null;
    },
    onRowEnter(event, info) {
      this.hoveredGroup = this.groupKey(info);
      if (this.patternTooltip) {
        this.patternTooltip.destroy();
        this.patternTooltip = null;
      }
      const ids = patternIdsFromInfo(info);
      if (ids.length > 0) {
        const anchor = event.currentTarget.querySelector('td.code') || event.currentTarget;
        const tooltip = showPatternTooltip(anchor, ids, {
          hideDelay: 1000,
          interactive: false,
          link: false,
          placement: 'source-row',
          onDestroy: () => {
            if (this.patternTooltip === tooltip) this.patternTooltip = null;
          }
        });
        this.patternTooltip = tooltip;
      }
    },
    onRowLeave() {
      this.hoveredGroup = null;
      if (this.patternTooltip) this.patternTooltip.scheduleDestroy();
    },
    matchStartId(line) {
      // Stable anchor for ReportDetails' navigation state - only emitted on
      // rows that begin an unresolved match.
      const info = line[1];
      if (info.risk !== 9 || !info.end) return null;
      return `line-${this.fileId}-${line[0]}`;
    },
    showActions(info) {
      return !this.readOnly && this.isAdminOrContributor && info.end;
    },
    canCorrect(line) {
      // File-browser correction button: the start row (info.end) of a snippet-backed region links to
      // the full-page snippet editor. Group-hover reveals it from anywhere in the region.
      const info = line[1];
      return this.linkEditor && this.isAdminOrContributor && info.snippet && info.end != null;
    },
    snippetActionLabel(info) {
      if (info.folded) return 'Correct this fold';
      if (info.cleared) return 'Review cleared text';
      return 'Create Pattern from selection';
    },
    isHiddenByEditor(line) {
      if (!this.inlineEditor) return false;
      return line[0] >= this.inlineEditor.startLine && line[0] <= this.inlineEditor.endLine;
    },
    actionsForLine(line) {
      const start = line[0];
      const end = line[1].end;
      const hash = line[1].hash;
      if (!end) return [];
      return this.pendingActions.filter(a => {
        if (a.startLine === start && a.endLine === end) return true;
        if (hash && a.hash === hash) return true;
        return false;
      });
    },
    onDismiss(action) {
      this.$emit('dismiss-action', action.id);
    },
    onCreateClick(event, line, snippetId) {
      event.preventDefault();
      this.$emit('open-editor', {
        snippetId: snippetId ?? null,
        fileId: this.fileId,
        startLine: line[0],
        endLine: line[1].end,
        hash: line[1].hash ?? null,
        from: this.packname,
        filePath: this.filename
      });
    },
    newSnippetUrl(start, end, hash) {
      const qs = new URLSearchParams({from: this.packname});
      if (hash) qs.set('hash', hash);
      return `/snippets/from_file/${this.fileId}/${start}/${end}?${qs.toString()}`;
    },
    editSnippetUrl(id, hash) {
      const params = {from: this.packname};
      if (hash) params.hash = hash;
      return `/snippet/edit/${id}?${new URLSearchParams(params).toString()}`;
    },
    editPatternUrl(id) {
      return `/licenses/edit_pattern/${id}`;
    },
    emitExtend(kind, line) {
      this.$emit('extend', {
        kind,
        start: line[0],
        end: line[1].end,
        prevstart: line[1].prevstart || 0,
        nextend: line[1].nextend || 0
      });
    },
    canExtendUp(line) {
      return !this.readOnly && this.isAdminOrContributor && line[1].risk === 9 && line[1].end && line[0] > 1;
    },
    canExtendDown(line) {
      return !this.readOnly && this.isAdminOrContributor && this.matchExtents.has(line[0]);
    },
    onExtendUp(event, line) {
      this.scheduleCompensation(event, 'one-line-above', line[0] - 1);
      this.emitExtend('one-line-above', line);
    },
    onExtendDown(event, endLine) {
      const meta = this.matchExtents.get(endLine);
      if (!meta) return;
      this.scheduleCompensation(event, 'one-line-below', endLine + 1);
      this.$emit('extend', {
        kind: 'one-line-below',
        start: meta.startLine,
        end: meta.endLine,
        prevstart: meta.prevstart,
        nextend: meta.nextend
      });
    },
    scheduleCompensation(event, kind, targetLine) {
      // Capture the button's viewport y BEFORE the re-render. The watcher on
      // `lines` measures again after the new source lands and scrolls the
      // window so the equivalent button lands at the same screen position,
      // letting the user hammer the affordance without re-aiming.
      const btn = event.currentTarget;
      if (!btn) return;
      this.pendingCompensation = {kind, targetLine, beforeTop: btn.getBoundingClientRect().top};
    }
  }
};
</script>

<style>
/* Stabilise the snippet table layout. With table-layout: auto, CodeMirror's
   measure cycle inside the inline pattern editor (in a <td colspan="4">)
   would feed its intrinsic content width back into the table's column
   distribution, and the editor would visibly resize while the user scrolled
   through long patterns. Fixed layout with explicit col widths breaks that
   loop — the editor's content can never push the column wider. */
.source .snippet {
  table-layout: fixed;
  width: 100%;
}
.source .snippet .snippet-col-actions,
.source .snippet .snippet-col-quick-actions {
  width: 28px;
}
.source .snippet .snippet-col-linenumber {
  width: 3.5em;
}
.snippet .inline-editor-row > td {
  background: #ffffff;
  border-top: 1px solid #d0d7de !important;
  border-bottom: 1px solid #d0d7de !important;
  padding: 12px 16px !important;
}
.snippet .inline-editor-row #inline-snippet-editor .snippet-editor {
  margin-top: 0;
}
.snippet.editor-open tr:not(.inline-editor-row) {
  opacity: 0.1;
  transition: opacity 0.15s ease-in-out;
}
.snippet td.actions,
.snippet td.quick-actions {
  padding-bottom: 0;
  padding-top: 0;
  position: relative;
  width: 28px;
}
.snippet td.code {
  position: relative;
}
/* Derived resolutions use a gutter cue (and cleared text is muted) so reviewers can tell a
   similarity-folded license / cleared boilerplate region from a curated pattern match at a glance. */
.snippet tr.folded td.linenumber,
.snippet tr.cleared td.linenumber {
  background-color: rgba(246, 248, 250, 0.88);
  border-left: 4px solid #6e7781;
  color: #57606a;
}
.snippet tr.cleared td.code {
  color: #6e7781;
  font-style: italic;
}
.snippet td.code .correct-btn {
  left: auto;
  right: 6px;
  top: 12px;
}
.snippet .snippet-tool-btn {
  align-items: center;
  background: rgba(255, 255, 255, 0.92);
  border: 1px solid #d0d7de;
  border-radius: 6px;
  box-shadow: 0 1px 2px rgba(31, 35, 40, 0.08);
  color: #1f2328;
  cursor: pointer;
  display: inline-flex;
  font-size: 13px;
  height: 24px;
  justify-content: center;
  opacity: 0;
  padding: 0;
  position: absolute;
  text-decoration: none;
  top: 10px;
  transform: translateY(-50%);
  transition:
    background-color 0.15s,
    box-shadow 0.15s,
    color 0.15s,
    opacity 0.15s;
  width: 24px;
  z-index: 2;
}
.snippet tr:hover .snippet-tool-btn,
.snippet tr.group-hovered .snippet-tool-btn,
.snippet .snippet-tool-btn:focus,
.snippet .snippet-tool-btn[aria-expanded='true'] {
  opacity: 1;
}
@media (hover: none) {
  .snippet .snippet-tool-btn {
    opacity: 1;
  }
}
.snippet td.actions .snippet-tool-btn {
  left: -4px;
}
.snippet td.quick-actions .snippet-tool-btn {
  right: -4px;
}
.snippet td.code .extend-vert-btn {
  left: 50%;
  top: auto;
  bottom: auto;
  transform: translateX(-50%);
  z-index: 3;
}
.snippet td.code .extend-up-btn {
  top: -12px;
}
.snippet td.code .extend-down-btn {
  bottom: -12px;
}
.source .snippet .snippet-tool-btn i {
  color: #1f2328;
}
.snippet .snippet-tool-btn:hover {
  background: #ffffff;
  box-shadow: 0 2px 4px rgba(31, 35, 40, 0.12);
  color: #0969da;
}
.source .snippet .snippet-tool-btn:hover i {
  color: #0969da;
}
.snippet .snippet-tool-btn:focus {
  border-color: #0969da;
  box-shadow: 0 0 0 3px rgba(9, 105, 218, 0.3);
  color: #0969da;
  outline: none;
}
.source .snippet .snippet-tool-btn:focus i {
  color: #0969da;
}
</style>
