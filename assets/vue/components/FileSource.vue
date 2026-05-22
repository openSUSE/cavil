<template>
  <table class="snippet" :class="{'editor-open': inlineEditor}">
    <tbody>
      <!-- eslint-disable-next-line vue/no-v-for-template-key -->
      <template v-for="(line, idx) in lines" :key="idx">
        <tr v-if="line[1].withgap">
          <td class="redbar" colspan="4"></td>
        </tr>
        <tr
          v-if="!isHiddenByEditor(line)"
          :id="matchStartId(line)"
          :class="rowClass(line[1])"
          :title="line[1].risk > 0 ? line[1].name : null"
          @mouseenter="onRowEnter(line[1])"
          @mouseleave="onRowLeave"
        >
          <td v-if="!showActions(line[1])" class="actions"></td>
          <td v-else class="actions dropdown show">
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
              <i class="actions-menu fa-solid fa-caret-down"></i>
            </a>
            <div class="dropdown-menu" :aria-labelledby="'dropdownMenuLink-' + fileId + '-' + line[0]">
              <template v-if="line[1].risk === 9">
                <a
                  v-if="line[1].snippet"
                  class="dropdown-item"
                  :href="editSnippetUrl(line[1].snippet, line[1].hash)"
                  @click="onCreateClick($event, line, line[1].snippet)"
                  >Create Pattern from selection</a
                >
                <a
                  v-else
                  class="dropdown-item"
                  :href="newSnippetUrl(line[0], line[1].end, line[1].hash)"
                  @click="onCreateClick($event, line, null)"
                  >Create Pattern from selection</a
                >
              </template>
              <a v-else class="dropdown-item" :href="editPatternUrl(line[1].pid)" target="_blank" rel="noopener"
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
          </td>

          <td v-if="line[1].end && line[1].risk === 9 && line[1].snippet" class="quick-actions">
            <a
              :href="newSnippetUrl(line[0], line[1].end, line[1].hash)"
              class="snippet-tool-btn"
              target="_blank"
              title="Create pattern from selection"
              aria-label="Create pattern from selection"
              @click="onCreateClick($event, line, line[1].snippet)"
            >
              <i class="fa-solid fa-plus"></i>
            </a>
          </td>
          <td v-else class="quick-actions"></td>
        </tr>
        <tr v-if="inlineEditor && inlineEditor.startLine === line[0]" class="inline-editor-row">
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
    inlineEditor: {type: Object, default: null}
  },
  emits: ['extend', 'open-editor', 'dismiss-action', 'close-editor', 'editor-submit'],
  data() {
    return {hoveredGroup: null};
  },
  computed: {
    isAdminOrContributor() {
      return this.hasAdminRole || this.hasContributorRole;
    }
  },
  methods: {
    rowClass(info) {
      const classes = [`risk-${info.risk}`];
      if (info.hash) classes.push(`hash-${info.hash}`);
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
    onRowEnter(info) {
      this.hoveredGroup = this.groupKey(info);
    },
    onRowLeave() {
      this.hoveredGroup = null;
    },
    matchStartId(line) {
      // Stable anchor for ReportDetails' navigation state - only emitted on
      // rows that begin an unresolved match.
      const info = line[1];
      if (info.risk !== 9 || !info.end) return null;
      return `line-${this.fileId}-${line[0]}`;
    },
    showActions(info) {
      return this.isAdminOrContributor && info.end;
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
    }
  }
};
</script>

<style>
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
  top: 50%;
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
