<template>
  <div class="upload-page">
    <cavil-notice-panel tone="warning" title="Experimental feature" icon="fa-solid fa-flask">
      <p class="cavil-notice-summary">
        Upload any archive supported by Cavil (tar.*, zip, rpm, 7z, …) for legal review. No metadata is required &mdash;
        the package name is taken from the filename and licenses are detected automatically.
      </p>
    </cavil-notice-panel>

    <div
      class="upload-dropzone"
      :class="{'is-dragging': isDragging, 'has-file': file !== null}"
      role="button"
      tabindex="0"
      @click="browse"
      @keydown.enter.prevent="browse"
      @keydown.space.prevent="browse"
      @dragover.prevent="isDragging = true"
      @dragenter.prevent="isDragging = true"
      @dragleave.prevent="isDragging = false"
      @drop.prevent="onDrop"
    >
      <input ref="fileInput" type="file" name="tarball" class="upload-file-input" @change="onPick" />
      <template v-if="file === null">
        <i class="fa-solid fa-cloud-arrow-up upload-dropzone-icon"></i>
        <div class="upload-dropzone-primary">
          Drag an archive here, or <span class="upload-dropzone-link">browse</span>
        </div>
        <div class="upload-dropzone-secondary">A single compressed source archive</div>
      </template>
      <template v-else>
        <i class="fa-solid fa-file-zipper upload-dropzone-icon"></i>
        <div class="upload-dropzone-primary" id="selected-file">{{ file.name }}</div>
        <div class="upload-dropzone-secondary">{{ humanSize }} &middot; click to choose a different file</div>
      </template>
    </div>

    <div class="row g-3 mt-1">
      <div class="col-md-8">
        <label class="form-label" for="upload-name">Name</label>
        <input
          id="upload-name"
          v-model="name"
          name="name"
          class="form-control"
          placeholder="perl-Mojolicious"
          autocomplete="off"
        />
        <div class="form-text">Prefilled from the filename, edit if needed.</div>
      </div>
      <div class="col-md-4">
        <label class="form-label" for="upload-priority">Priority</label>
        <select id="upload-priority" v-model="priority" name="priority" class="form-select">
          <option v-for="p in 8" :key="p" :value="String(p)">{{ p }}</option>
        </select>
      </div>
    </div>

    <div v-if="uploading || progress > 0" class="mt-3">
      <div class="progress" role="progressbar" :aria-valuenow="progress" aria-valuemin="0" aria-valuemax="100">
        <div
          class="progress-bar progress-bar-striped progress-bar-animated"
          id="upload-progress"
          :style="{width: progress + '%'}"
        >
          {{ progress }}%
        </div>
      </div>
    </div>

    <cavil-notice-panel
      v-if="error !== null"
      tone="warning"
      title="Upload failed"
      icon="fa-solid fa-triangle-exclamation"
    >
      <p class="cavil-notice-summary" id="upload-error">{{ error }}</p>
    </cavil-notice-panel>

    <div class="mt-3">
      <button id="upload-button" class="btn btn-primary" :disabled="!canUpload" @click="upload">
        <i v-if="uploading" class="fa-solid fa-rotate fa-spin"></i>
        {{ uploading ? 'Uploading…' : 'Upload' }}
      </button>
    </div>
  </div>
</template>

<script>
import CavilNoticePanel from './components/CavilNoticePanel.vue';

// Derive a default package name from the filename: drop the directory, then everything from
// the first dot (file extensions plus the version's dotted tail), then a trailing
// dash-delimited version (numbers and dots), and finally keep only valid name characters
function nameFromFilename(filename) {
  const stem = filename
    .replace(/^.*[\\/]/, '')
    .replace(/\..*$/, '')
    .replace(/-[0-9][0-9.]*$/, '');
  return stem.replace(/[^A-Za-z0-9.-]+/g, '-').replace(/^-+|-+$/g, '');
}

export default {
  name: 'ArchiveUpload',
  components: {CavilNoticePanel},
  data() {
    return {
      file: null,
      name: '',
      priority: '5',
      isDragging: false,
      uploading: false,
      progress: 0,
      error: null
    };
  },
  computed: {
    canUpload() {
      return this.file !== null && this.name.trim() !== '' && !this.uploading;
    },
    humanSize() {
      if (this.file === null) return '';
      let size = this.file.size;
      const units = ['B', 'KB', 'MB', 'GB'];
      let unit = 0;
      while (size >= 1024 && unit < units.length - 1) {
        size /= 1024;
        unit++;
      }
      return `${size.toFixed(unit === 0 ? 0 : 1)} ${units[unit]}`;
    }
  },
  methods: {
    browse() {
      this.$refs.fileInput.click();
    },
    onPick(event) {
      const files = event.target.files;
      if (files.length > 0) this.selectFile(files[0]);
    },
    onDrop(event) {
      this.isDragging = false;
      const files = event.dataTransfer.files;
      if (files.length > 0) this.selectFile(files[0]);
    },
    selectFile(file) {
      this.file = file;
      this.error = null;
      this.progress = 0;
      if (this.name.trim() === '') this.name = nameFromFilename(file.name);
    },
    upload() {
      if (!this.canUpload) return;
      this.uploading = true;
      this.error = null;
      this.progress = 0;

      const form = new FormData();
      form.append('name', this.name.trim());
      form.append('priority', this.priority);
      form.append('tarball', this.file);

      const xhr = new XMLHttpRequest();
      xhr.open('POST', this.storeUrl);
      xhr.setRequestHeader('Accept', 'application/json');
      xhr.upload.onprogress = event => {
        if (event.lengthComputable) this.progress = Math.round((event.loaded / event.total) * 100);
      };
      xhr.onload = () => {
        let data = {};
        try {
          data = JSON.parse(xhr.responseText);
        } catch {
          data = {};
        }
        if (xhr.status >= 200 && xhr.status < 300 && data.url) {
          this.progress = 100;
          window.location.assign(data.url);
        } else {
          this.uploading = false;
          this.progress = 0;
          this.error = data.error || `Upload failed (status ${xhr.status})`;
        }
      };
      xhr.onerror = () => {
        this.uploading = false;
        this.progress = 0;
        this.error = 'Upload failed, the server could not be reached';
      };
      xhr.send(form);
    }
  }
};
</script>

<style>
.upload-page {
  margin-top: 1rem;
}
.upload-dropzone {
  align-items: center;
  background: #f6f8fa;
  border: 2px dashed #d0d7de;
  border-radius: 8px;
  cursor: pointer;
  display: flex;
  flex-direction: column;
  gap: 0.35rem;
  justify-content: center;
  padding: 2.5rem 1rem;
  text-align: center;
  transition:
    border-color 0.15s ease,
    background 0.15s ease;
}
.upload-dropzone:hover,
.upload-dropzone:focus {
  border-color: #0969da;
  outline: none;
}
.upload-dropzone.is-dragging {
  background: #ddf4ff;
  border-color: #0969da;
}
.upload-dropzone.has-file {
  background: #ffffff;
  border-style: solid;
}
.upload-file-input {
  display: none;
}
.upload-dropzone-icon {
  color: #6e7781;
  font-size: 1.75rem;
}
.upload-dropzone-primary {
  color: #1f2328;
  font-size: 15px;
  font-weight: 600;
  overflow-wrap: anywhere;
}
.upload-dropzone-link {
  color: #0969da;
}
.upload-dropzone-secondary {
  color: #57606a;
  font-size: 13px;
}
</style>
