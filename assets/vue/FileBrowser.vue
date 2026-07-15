<template>
  <div class="file-browser">
    <div v-if="loading && !meta" class="file-browser-loading">
      <LegalLoading message="Opening case files..." size="full" />
    </div>
    <div v-else-if="error" class="alert alert-danger file-browser-error">{{ error }}</div>
    <div v-else-if="meta">
      <div v-if="editorError" class="alert alert-danger file-browser-error" role="alert">{{ editorError }}</div>
      <div class="file-browser-header">
        <div class="file-browser-title">
          <a :href="meta.package.detailsUrl" class="file-browser-package">
            <i class="fa-solid fa-box"></i>
            {{ meta.package.name }}
          </a>
          <span class="file-browser-checkout">{{ meta.checkoutDir }}</span>
        </div>
      </div>

      <nav class="file-browser-breadcrumb" aria-label="File path">
        <span v-for="(crumb, index) in meta.breadcrumbs" :key="crumb.path" class="file-browser-breadcrumb-item">
          <span v-if="index > 0" class="file-browser-separator">/</span>
          <a :href="crumb.url" @click="openPath($event, crumb.path)">{{ crumb.name }}</a>
        </span>
        <span class="file-browser-count">
          <template v-if="meta.kind === 'directory'">
            {{ meta.entries.length }} {{ meta.entries.length === 1 ? 'item' : 'items' }}
          </template>
          <template v-else-if="sourceIsOversized">{{ meta.source.sizeLabel }} file</template>
          <template v-else
            >{{ meta.source.lines.length }} {{ meta.source.lines.length === 1 ? 'line' : 'lines' }}</template
          >
        </span>
      </nav>

      <div v-if="meta.kind === 'directory'" class="file-browser-panel">
        <table class="file-browser-table">
          <tbody>
            <tr v-for="entry in meta.entries" :key="entry.path" :class="{'has-match': entry.hasMatch}">
              <td class="file-browser-icon">
                <i v-if="entry.kind === 'directory'" class="fa-solid fa-folder"></i>
                <i v-else-if="entry.processed" class="fa-regular fa-copy"></i>
                <i v-else class="fa-regular fa-file"></i>
              </td>
              <td class="file-browser-name">
                <a :href="entry.url" @click="openPath($event, entry.path)">{{ entry.name }}</a>
              </td>
              <td class="file-browser-kind">
                <span v-if="entry.hasMatch" class="file-browser-match-badge">matched</span>
                <span v-else-if="entry.processed">processed</span>
                <span v-else>{{ entry.kind }}</span>
              </td>
            </tr>
            <tr v-if="meta.entries.length === 0">
              <td colspan="3" class="file-browser-empty">No files in this directory.</td>
            </tr>
          </tbody>
        </table>
      </div>

      <div v-else class="file-browser-panel file-browser-source-panel">
        <div v-if="sourceIsOversized" class="file-browser-too-large" role="status">
          <i class="fa-regular fa-file-lines"></i>
          <strong>This file is too large to display.</strong>
          <span
            >{{ meta.source.filename }} is {{ meta.source.sizeLabel }}. The display limit is
            {{ meta.source.maxSizeLabel }}.</span
          >
        </div>
        <div v-else class="source file-browser-source">
          <FileSource
            :lines="meta.source.lines"
            :file-id="meta.source.id || 0"
            :filename="meta.source.filename"
            :packname="meta.source.name"
            :has-admin-role="hasAdminRole"
            :has-contributor-role="hasContributorRole"
            :pending-actions="pendingActionsForCurrentFile"
            :inline-editor="openInlineEditor"
            @extend="onExtend"
            @open-editor="openEditor"
            @dismiss-action="dismissAction"
            @close-editor="closeInlineEditor"
            @editor-submit="onEditorSubmit"
          />
        </div>
      </div>
      <PendingActionsWidget v-if="isAdminOrContributor && pendingActions.length > 0" />
    </div>
  </div>
</template>

<script>
import FileSource from './components/FileSource.vue';
import LegalLoading from './components/LegalLoading.vue';
import PendingActionsWidget from './components/PendingActionsWidget.vue';
import {encodePath, fileViewUrl} from './helpers/links.js';
import {resolveSnippetFromFile, submitSnippetDecisions} from './helpers/snippetDecisions.js';

let openEditorKeySeq = 0;
let pendingActionIdSeq = 0;

export default {
  name: 'FileBrowser',
  components: {FileSource, LegalLoading, PendingActionsWidget},
  provide() {
    return {
      pendingActionsStore: {
        actions: this.pendingActions,
        add: action => this.pendingActions.push(action),
        remove: id => this.dismissAction(id),
        clear: () => {
          this.pendingActions.splice(0, this.pendingActions.length);
        },
        edit: id => this.editAction(id),
        scrollTo: id => this.scrollToAction(id),
        submitAll: () => this.submitAllActions()
      }
    };
  },
  data() {
    return {
      error: null,
      hasAdminRole: this.hasAdminRole ?? false,
      hasContributorRole: this.hasContributorRole ?? false,
      initialPath: this.fileBrowserInitialPath ?? '',
      loading: false,
      meta: null,
      editorError: null,
      openInlineEditor: null,
      pendingActions: [],
      pkgId: this.pkgId
    };
  },
  computed: {
    isAdminOrContributor() {
      return this.hasAdminRole || this.hasContributorRole;
    },
    pendingActionsForCurrentFile() {
      if (!this.meta || this.meta.kind !== 'file') return [];
      return this.pendingActions.filter(a => a.fileId === this.meta.source.id);
    },
    sourceIsOversized() {
      return this.meta && this.meta.kind === 'file' && this.meta.source && this.meta.source.oversized;
    }
  },
  mounted() {
    window.addEventListener('popstate', this.onPopState);
    this.fetchPath(this.initialPath, {replace: true});
  },
  beforeUnmount() {
    window.removeEventListener('popstate', this.onPopState);
  },
  methods: {
    metaUrl(path) {
      return `/reviews/file_view_meta/${this.pkgId}/${encodePath(path)}`;
    },
    viewUrl(path) {
      return fileViewUrl(this.pkgId, path);
    },
    async fetchPath(path, options = {}) {
      this.loading = true;
      this.error = null;
      this.editorError = null;
      try {
        const res = await fetch(this.metaUrl(path));
        if (!res.ok) {
          this.error = `Could not load file browser data (HTTP ${res.status}).`;
          return;
        }
        this.meta = await res.json();
        this.openInlineEditor = null;
        document.title =
          this.meta.kind === 'directory'
            ? `Directory listing of ${this.meta.currentPath || '/'}`
            : `Content of ${this.meta.currentPath}`;
        const nextUrl = this.viewUrl(this.meta.currentPath);
        if (options.replace) history.replaceState({path: this.meta.currentPath}, '', nextUrl);
        else history.pushState({path: this.meta.currentPath}, '', nextUrl);
      } finally {
        this.loading = false;
      }
    },
    openPath(event, path) {
      if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || event.button !== 0) return;
      event.preventDefault();
      this.fetchPath(path);
    },
    onPopState() {
      const prefix = `/reviews/file_view/${this.pkgId}`;
      let path = window.location.pathname.startsWith(prefix) ? window.location.pathname.slice(prefix.length) : '';
      path = path.replace(/^\//, '');
      this.fetchPath(decodeURIComponent(path), {replace: true});
    },
    async fetchSource(start = 0, end = 0) {
      if (!this.meta || this.meta.kind !== 'file' || !this.meta.source.id) return;
      const qs = new URLSearchParams();
      if (start) qs.set('start', start);
      if (end) qs.set('end', end);
      const url = `/reviews/fetch_source/${this.meta.source.id}.json${qs.toString() ? '?' + qs.toString() : ''}`;
      const res = await fetch(url);
      if (!res.ok) return;
      const data = await res.json();
      this.meta.source = {id: this.meta.source.id, ...data.source};
    },
    onExtend(payload) {
      if (payload.kind === 'reset') return this.fetchPath(this.meta.currentPath, {replace: true});

      let start = Number(payload.start);
      let end = Number(payload.end);
      switch (payload.kind) {
        case 'one-line-above':
          start -= 1;
          break;
        case 'one-line-below':
          end += 1;
          break;
        case 'top':
          start = 1;
          break;
        case 'bottom':
          end += 3000;
          break;
        case 'match-above':
          start = Number(payload.prevstart);
          break;
        case 'match-below':
          end = Number(payload.nextend);
          break;
      }
      this.fetchSource(start, end);
    },
    async openEditor(meta) {
      this.editorError = null;
      let snippetId = meta.snippetId;
      try {
        if (snippetId === null) {
          const data = await resolveSnippetFromFile(meta);
          snippetId = data.snippet;
        }
      } catch (err) {
        this.editorError = err.message ?? String(err);
        return;
      }
      await this.showInlineEditor({
        snippetId,
        fileId: meta.fileId,
        startLine: meta.startLine,
        endLine: meta.endLine,
        hash: meta.hash ?? null,
        from: meta.from ?? null,
        filePath: meta.filePath ?? null,
        initial: null
      });
    },
    async showInlineEditor(payload) {
      this.openInlineEditor = {...payload, key: ++openEditorKeySeq};
      await this.$nextTick();
      const el = document.getElementById('inline-snippet-editor');
      if (el) el.scrollIntoView({block: 'nearest'});
    },
    closeInlineEditor() {
      this.openInlineEditor = null;
    },
    onEditorSubmit(payload) {
      const ctx = this.openInlineEditor ?? {};
      const editingId = ctx.editingId ?? null;
      const existingIdx = editingId !== null ? this.pendingActions.findIndex(a => a.id === editingId) : -1;
      const baseId = existingIdx >= 0 ? this.pendingActions[existingIdx].id : ++pendingActionIdSeq;
      const action = {
        id: baseId,
        snippetId: ctx.snippetId,
        fileId: ctx.fileId,
        startLine: ctx.startLine,
        endLine: ctx.endLine,
        hash: ctx.hash,
        from: ctx.from,
        filePath: ctx.filePath,
        action: payload.action,
        formData: payload.formData,
        license: payload.license || (payload.formData && payload.formData.license) || '',
        locationLabel: `${ctx.filePath ?? `file ${ctx.fileId}`}:${ctx.startLine}-${ctx.endLine}`,
        state: 'pending',
        error: null
      };
      if (existingIdx >= 0) {
        this.pendingActions.splice(existingIdx, 1, action);
      } else {
        this.pendingActions.push(action);
      }
      this.closeInlineEditor();
    },
    dismissAction(id) {
      const idx = this.pendingActions.findIndex(a => a.id === id);
      if (idx >= 0) this.pendingActions.splice(idx, 1);
    },
    async scrollToAction(id) {
      const action = this.pendingActions.find(a => a.id === id);
      if (!action) return;
      if (action.filePath && (!this.meta || this.meta.kind !== 'file' || this.meta.currentPath !== action.filePath)) {
        await this.fetchPath(action.filePath);
      }
      await this.$nextTick();
      const indicator = document.getElementById('pending-indicator-' + id);
      const fallback = document.querySelector('.file-browser-source');
      const target = indicator || fallback;
      if (target) target.scrollIntoView({behavior: 'smooth', block: 'center'});
    },
    async editAction(id) {
      const action = this.pendingActions.find(a => a.id === id);
      if (!action) return;
      if (action.filePath && (!this.meta || this.meta.kind !== 'file' || this.meta.currentPath !== action.filePath)) {
        await this.fetchPath(action.filePath);
      }
      await this.showInlineEditor({
        snippetId: action.snippetId,
        fileId: action.fileId,
        startLine: action.startLine,
        endLine: action.endLine,
        hash: action.hash,
        from: action.from,
        filePath: action.locationLabel.split(':')[0],
        initial: action.formData,
        editingId: action.id
      });
    },
    async submitAllActions() {
      const queue = this.pendingActions.filter(a => a.state !== 'done');
      if (queue.length === 0) return;

      for (const action of queue) {
        action.state = 'submitting';
        action.error = null;
      }

      let res;
      let data;
      let results;
      try {
        ({res, data, results} = await submitSnippetDecisions(
          queue.map(a => ({kind: a.action, snippetId: a.snippetId, formData: a.formData}))
        ));
      } catch (err) {
        for (const action of queue) {
          action.state = 'error';
          action.error = err.message ?? String(err);
        }
        return;
      }

      if (res.isSuccess && data && data.ok) {
        this.pendingActions.splice(0, this.pendingActions.length);
        this.closeInlineEditor();
        await this.fetchPath(this.meta.currentPath, {replace: true});
        return;
      }

      for (let i = 0; i < queue.length; i++) {
        const action = queue[i];
        const result = results[i];
        if (result && result.error) {
          action.state = 'error';
          action.error = result.error;
        } else if (result && result.ok) {
          action.state = 'pending';
          action.error = null;
        } else {
          action.state = 'error';
          action.error = (data && data.error) || `Request failed (HTTP ${res.statusCode})`;
        }
      }
    }
  }
};
</script>

<style>
.file-browser {
  color: #1f2328;
  margin-top: 1rem;
}
.file-browser-loading {
  color: #59636e;
  padding: 24px 0;
}
.file-browser-header {
  align-items: center;
  border: 1px solid #d0d7de;
  border-radius: 6px 6px 0 0;
  display: flex;
  justify-content: space-between;
  padding: 12px 16px;
}
.file-browser-title {
  align-items: center;
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  min-width: 0;
}
.file-browser-package {
  align-items: center;
  color: #0969da;
  display: inline-flex;
  font-size: 16px;
  font-weight: 600;
  gap: 8px;
  text-decoration: none;
}
.file-browser-package:hover,
.file-browser-breadcrumb a:hover,
.file-browser-name a:hover {
  text-decoration: underline;
}
.file-browser-checkout,
.file-browser-match-badge {
  border: 1px solid #d0d7de;
  border-radius: 2em;
  color: #59636e;
  font-size: 12px;
  line-height: 18px;
  padding: 0 7px;
  white-space: nowrap;
}
.file-browser-breadcrumb {
  align-items: center;
  background: #f6f8fa;
  border: 1px solid #d0d7de;
  border-top: 0;
  display: flex;
  flex-wrap: wrap;
  font-size: 14px;
  gap: 6px;
  padding: 10px 16px;
}
.file-browser-count {
  color: #59636e;
  font-size: 12px;
  margin-left: auto;
  white-space: nowrap;
}
.file-browser-breadcrumb-item {
  display: inline-flex;
  gap: 6px;
}
.file-browser-breadcrumb a {
  color: #0969da;
  font-weight: 600;
  text-decoration: none;
}
.file-browser-separator {
  color: #59636e;
}
.file-browser-panel {
  border: 1px solid #d0d7de;
  border-radius: 0 0 6px 6px;
  border-top: 0;
  margin-bottom: 24px;
}
.file-browser-table {
  border-collapse: collapse;
  font-size: 14px;
  width: 100%;
}
.file-browser-table tr {
  border-bottom: 1px solid #d8dee4;
}
.file-browser-table tr:last-child {
  border-bottom: 0;
}
.file-browser-table tr:hover {
  background: #f6f8fa;
}
.file-browser-table td {
  padding: 8px 10px;
}
.file-browser-icon {
  color: #59636e;
  text-align: center;
  width: 36px;
}
.file-browser-table .has-match .file-browser-icon {
  color: #cf222e;
}
.file-browser-name a {
  color: #0969da;
  text-decoration: none;
}
.file-browser-kind {
  color: #59636e;
  font-size: 12px;
  text-align: right;
  white-space: nowrap;
  width: 120px;
}
.file-browser-match-badge {
  background: rgba(207, 34, 46, 0.08);
  border-color: rgba(207, 34, 46, 0.2);
  color: #cf222e;
}
.file-browser-empty {
  color: #59636e;
  padding: 24px 16px !important;
  text-align: center;
}
.file-browser-source.source {
  border: 0 !important;
  border-radius: 0;
  margin: 0;
}
.file-browser-source .snippet {
  margin-bottom: 0;
  width: 100%;
}
.file-browser-source .snippet tr.has-pattern-tooltip td.code {
  cursor: help;
}
.file-browser-too-large {
  align-items: center;
  color: #59636e;
  display: flex;
  flex-direction: column;
  gap: 8px;
  justify-content: center;
  min-height: 220px;
  padding: 32px 16px;
  text-align: center;
}
.file-browser-too-large i {
  color: #8c959f;
  font-size: 32px;
}
.file-browser-too-large strong {
  color: #1f2328;
  font-size: 16px;
}
.cavil-pattern-tip-floating {
  position: fixed;
  z-index: 1080;
}
@media (max-width: 640px) {
  .file-browser-header {
    align-items: flex-start;
    flex-direction: column;
    gap: 8px;
  }
  .file-browser-kind {
    display: none;
  }
}
</style>
