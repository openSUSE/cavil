<template>
  <div class="markdown-composer">
    <div class="markdown-composer-tabs" role="tablist">
      <button
        type="button"
        class="markdown-composer-tab"
        :class="{active: mode === 'write'}"
        role="tab"
        :aria-selected="mode === 'write'"
        :data-composer-tab="`write-${dataAttr}`"
        @click="setMode('write')"
      >
        <i class="fa-solid fa-pen-to-square"></i> Write
      </button>
      <button
        type="button"
        class="markdown-composer-tab"
        :class="{active: mode === 'preview'}"
        role="tab"
        :aria-selected="mode === 'preview'"
        :disabled="!trimmed"
        :data-composer-tab="`preview-${dataAttr}`"
        @click="setMode('preview')"
      >
        <i class="fa-regular fa-eye"></i> Preview
      </button>
    </div>

    <div v-show="mode === 'write'" class="markdown-composer-write">
      <textarea
        ref="textarea"
        :value="modelValue"
        class="form-control markdown-composer-textarea"
        :placeholder="placeholder"
        rows="5"
        :data-composer-input="dataAttr"
        @input="onInput"
        @keydown.meta.enter.prevent="emitSave"
        @keydown.ctrl.enter.prevent="emitSave"
      ></textarea>
    </div>

    <div v-show="mode === 'preview'" class="markdown-composer-preview" :data-composer-preview="dataAttr">
      <div v-if="previewLoading" class="markdown-composer-preview-loading">
        <i class="fa-solid fa-spinner fa-pulse"></i> Rendering preview…
      </div>
      <div v-else-if="previewError" class="markdown-composer-preview-error">
        <i class="fa-solid fa-triangle-exclamation"></i> {{ previewError }}
      </div>
      <div v-else-if="previewHtml" class="markdown-composer-preview-body markdown-body" v-html="previewHtml"></div>
      <div v-else class="markdown-composer-preview-empty">Nothing to preview.</div>
    </div>

    <div class="markdown-composer-actions">
      <slot name="leading"></slot>
      <span v-if="error" class="markdown-composer-error">{{ error }}</span>
      <button
        v-if="$attrs.onCancel"
        type="button"
        class="btn markdown-composer-cancel"
        :data-composer-cancel="dataAttr"
        @click="$emit('cancel')"
      >
        Cancel
      </button>
      <button
        type="button"
        class="btn btn-success markdown-composer-save"
        :disabled="saving || !trimmed"
        :data-composer-save="dataAttr"
        @click="emitSave"
      >
        <i v-if="saving" class="fa-solid fa-spinner fa-pulse"></i>
        <span v-else>{{ saving ? saveBusyLabel : saveLabel }}</span>
      </button>
    </div>
  </div>
</template>

<script>
import UserAgent from '@mojojs/user-agent';

export default {
  name: 'MarkdownComposer',
  inheritAttrs: false,
  props: {
    modelValue: {type: String, default: ''},
    placeholder: {type: String, default: 'Use Markdown for formatting.'},
    saving: {type: Boolean, default: false},
    error: {type: String, default: null},
    saveLabel: {type: String, default: 'Save'},
    saveBusyLabel: {type: String, default: 'Saving…'},
    dataAttr: {type: String, default: 'composer'}
  },
  emits: ['update:modelValue', 'save', 'cancel'],
  data() {
    return {
      mode: 'write',
      previewHtml: '',
      previewLoading: false,
      previewError: null,
      lastPreviewSource: null,
      ua: new UserAgent({baseURL: window.location.href})
    };
  },
  computed: {
    trimmed() {
      return (this.modelValue || '').trim().length > 0;
    }
  },
  methods: {
    onInput(event) {
      this.$emit('update:modelValue', event.target.value);
    },
    emitSave() {
      if (this.saving || !this.trimmed) return;
      this.$emit('save');
    },
    async setMode(mode) {
      if (mode === 'preview' && !this.trimmed) return;
      this.mode = mode;
      if (mode === 'preview') await this.refreshPreview();
    },
    async refreshPreview() {
      const body = (this.modelValue || '').trim();
      if (body === '') {
        this.previewHtml = '';
        return;
      }
      if (body === this.lastPreviewSource && this.previewHtml) return;
      this.previewLoading = true;
      this.previewError = null;
      try {
        const res = await this.ua.post('/reviews/notes/preview', {form: {body}});
        if (!res.isSuccess) {
          this.previewError = `Preview failed (HTTP ${res.statusCode})`;
          return;
        }
        const data = await res.json();
        this.previewHtml = data.html ?? '';
        this.lastPreviewSource = body;
      } catch (err) {
        this.previewError = err.message || 'Preview failed';
      } finally {
        this.previewLoading = false;
      }
    }
  }
};
</script>

<style>
.markdown-composer {
  background: #ffffff;
  border: 1px solid #d0d7de;
  border-radius: 6px;
  overflow: hidden;
}
.markdown-composer-tabs {
  background: #f6f8fa;
  border-bottom: 1px solid #d0d7de;
  display: flex;
  gap: 4px;
  padding: 6px 8px 0;
}
.markdown-composer-tab {
  align-items: center;
  background: transparent;
  border: 1px solid transparent;
  border-bottom: 0;
  border-radius: 6px 6px 0 0;
  color: #57606a;
  cursor: pointer;
  display: inline-flex;
  font-size: 13px;
  font-weight: 500;
  gap: 6px;
  line-height: 1;
  margin-bottom: -1px;
  padding: 8px 14px;
}
.markdown-composer-tab:hover:not(:disabled):not(.active) {
  background: #eef0f3;
  color: #1f2328;
}
.markdown-composer-tab.active {
  background: #ffffff;
  border-color: #d0d7de;
  color: #1f2328;
  font-weight: 600;
}
.markdown-composer-tab:disabled {
  color: #afb8c1;
  cursor: not-allowed;
}
.markdown-composer-write,
.markdown-composer-preview {
  padding: 10px 12px;
}
.markdown-composer-textarea {
  background: #ffffff;
  border: 1px solid #d0d7de;
  border-radius: 6px;
  font-size: 14px;
  line-height: 1.45;
  min-height: 110px;
  resize: vertical;
}
.markdown-composer-textarea:focus {
  border-color: #0969da;
  box-shadow: 0 0 0 3px rgba(9, 105, 218, 0.3);
  outline: none;
}
.markdown-composer-preview {
  min-height: 110px;
}
.markdown-composer-preview-loading,
.markdown-composer-preview-empty {
  align-items: center;
  color: #57606a;
  display: flex;
  gap: 8px;
  justify-content: center;
  padding: 32px 0;
}
.markdown-composer-preview-error {
  align-items: center;
  color: #cf222e;
  display: flex;
  gap: 8px;
  padding: 12px 4px;
}
.markdown-composer-preview-body {
  color: #1f2328;
  font-size: 14px;
  line-height: 1.5;
}
.markdown-composer-preview-body p:last-child {
  margin-bottom: 0;
}
.markdown-composer-preview-body pre {
  background: #f6f8fa;
  border-radius: 6px;
  padding: 10px;
}
.markdown-composer-preview-body code {
  background: rgba(175, 184, 193, 0.2);
  border-radius: 4px;
  font-size: 85%;
  padding: 0.2em 0.4em;
}
.markdown-composer-preview-body pre code {
  background: transparent;
  padding: 0;
}
.markdown-composer-actions {
  align-items: center;
  background: #f6f8fa;
  border-top: 1px solid #d0d7de;
  display: flex;
  flex-wrap: wrap;
  gap: 12px;
  justify-content: flex-end;
  padding: 8px 12px;
}
.markdown-composer-cancel {
  background-color: #f6f8fa;
  border: 1px solid rgba(31, 35, 40, 0.15);
  color: #1f2328;
  font-size: 13px;
  padding: 5px 14px;
}
.markdown-composer-cancel:hover {
  background-color: #eef0f3;
}
.markdown-composer-save {
  font-size: 13px;
  padding: 5px 16px;
}
.markdown-composer-error {
  color: #cf222e;
  font-size: 12px;
  margin-right: auto;
}
</style>
