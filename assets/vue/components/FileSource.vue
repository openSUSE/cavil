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
          :id="'line-' + fileId + '-' + line[0]"
          :class="rowClass(line[1])"
          :title="line[1].risk > 0 ? line[1].name : null"
        >
          <td v-if="!showActions(line[1])" class="actions"></td>
          <td v-else class="actions dropdown show">
            <a
              href="#"
              :id="'dropdownMenuLink-' + fileId + '-' + line[0]"
              data-bs-toggle="dropdown"
              aria-haspopup="true"
              aria-expanded="false"
            >
              <i class="actions-menu fa-solid fa-square-caret-down" title="Open Action Menu"></i>
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
              <a v-else class="dropdown-item" :href="editPatternUrl(line[1].pid)">Show Pattern</a>

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

          <td v-if="line[1].end && line[1].risk === 9 && line[1].snippet" class="quick-actions text-end">
            <a
              :href="newSnippetUrl(line[0], line[1].end, line[1].hash)"
              target="_blank"
              title="Create pattern from selection"
              @click="onCreateClick($event, line, line[1].snippet)"
            >
              <i class="fa-solid fa-square-plus"></i>
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
                :has-contributor-role="isAdminOrContributor"
                :has-admin-role="isAdminOrContributor"
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
    isAdminOrContributor: {type: Boolean, default: false},
    pendingActions: {type: Array, default: () => []},
    inlineEditor: {type: Object, default: null}
  },
  emits: ['extend', 'open-editor', 'dismiss-action', 'close-editor', 'editor-submit'],
  methods: {
    rowClass(info) {
      const classes = [`risk-${info.risk}`];
      if (info.hash) classes.push(`hash-${info.hash}`);
      return classes;
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
  opacity: 0.2;
  transition: opacity 0.15s ease-in-out;
}
</style>
