<template>
  <div class="file-browser">
    <div v-if="loading && !meta" class="file-browser-loading">
      <i class="fa-solid fa-rotate fa-spin"></i> Loading files...
    </div>
    <div v-else-if="error" class="alert alert-danger file-browser-error">{{ error }}</div>
    <div v-else-if="meta">
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
        <div class="source file-browser-source">
          <FileSource
            :lines="meta.source.lines"
            :file-id="meta.source.id || 0"
            :filename="meta.source.filename"
            :packname="meta.source.name"
            read-only
          />
        </div>
      </div>
    </div>
  </div>
</template>

<script>
import FileSource from './components/FileSource.vue';

export default {
  name: 'FileBrowser',
  components: {FileSource},
  data() {
    return {
      error: null,
      initialPath: this.fileBrowserInitialPath ?? '',
      loading: false,
      meta: null,
      pkgId: this.pkgId
    };
  },
  mounted() {
    window.addEventListener('popstate', this.onPopState);
    this.fetchPath(this.initialPath, {replace: true});
  },
  beforeUnmount() {
    window.removeEventListener('popstate', this.onPopState);
  },
  methods: {
    encodePath(path) {
      return path
        .split('/')
        .filter(part => part.length > 0)
        .map(part => encodeURIComponent(part))
        .join('/');
    },
    metaUrl(path) {
      const encoded = this.encodePath(path);
      return `/reviews/file_view_meta/${this.pkgId}/${encoded}`;
    },
    viewUrl(path) {
      const encoded = this.encodePath(path);
      return `/reviews/file_view/${this.pkgId}/${encoded}`;
    },
    async fetchPath(path, options = {}) {
      this.loading = true;
      this.error = null;
      try {
        const res = await fetch(this.metaUrl(path));
        if (!res.ok) {
          this.error = `Could not load file browser data (HTTP ${res.status}).`;
          return;
        }
        this.meta = await res.json();
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
