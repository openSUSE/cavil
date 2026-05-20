<template>
  <div
    class="modal fade"
    id="snippet-editor-modal"
    tabindex="-1"
    aria-labelledby="snippet-editor-modal-label"
    aria-hidden="true"
    ref="modalEl"
  >
    <div class="modal-dialog modal-xl modal-dialog-scrollable">
      <div class="modal-content">
        <div class="modal-header">
          <h5 class="modal-title" id="snippet-editor-modal-label">
            <i class="fa-solid fa-code-compare"></i>
            {{ title }}
          </h5>
          <button type="button" class="btn-close" aria-label="Close" @click="close"></button>
        </div>
        <div class="modal-body">
          <SnippetEditor
            v-if="snippetId !== null"
            :key="editorKey"
            ref="editor"
            :snippet-id="snippetId"
            :hash="hash"
            :from="from"
            :initial="initial"
            :has-contributor-role="hasContributorRole"
            :has-admin-role="hasAdminRole"
            mode="batch"
            @submit="onSubmit"
          />
        </div>
      </div>
    </div>
  </div>
</template>

<script>
import SnippetEditor from './SnippetEditor.vue';
import {Modal} from 'bootstrap';

export default {
  name: 'SnippetEditorModal',
  components: {SnippetEditor},
  props: {
    hasContributorRole: {type: Boolean, default: false},
    hasAdminRole: {type: Boolean, default: false}
  },
  emits: ['submit'],
  data() {
    return {
      snippetId: null,
      hash: null,
      from: null,
      context: null,
      initial: null,
      editingId: null,
      openCount: 0,
      modal: null
    };
  },
  computed: {
    title() {
      if (this.context === null) return 'Resolve match';
      const path = this.context.filePath ?? `file ${this.context.fileId}`;
      return `Resolve match in ${path}`;
    },
    editorKey() {
      // Force a fresh SnippetEditor instance for each open() call so the
      // `initial` prop is picked up by data() / mounted() on a clean component.
      return `${this.snippetId}-${this.openCount}`;
    }
  },
  mounted() {
    this.modal = new Modal(this.$refs.modalEl, {backdrop: 'static'});
    this.$refs.modalEl.addEventListener('hidden.bs.modal', () => {
      this.snippetId = null;
      this.context = null;
      this.initial = null;
      this.editingId = null;
    });
    this.$refs.modalEl.addEventListener('shown.bs.modal', () => {
      // CodeMirror was initialized while the modal was display:none and so
      // measured zero dimensions; refresh now that the textarea is visible.
      this.$nextTick(() => {
        if (this.$refs.editor) this.$refs.editor.refreshEditor();
      });
    });
  },
  beforeUnmount() {
    if (this.modal) {
      this.modal.dispose();
      this.modal = null;
    }
  },
  methods: {
    open({snippetId, hash, from, context, initial, editingId}) {
      this.snippetId = snippetId;
      this.hash = hash ?? null;
      this.from = from ?? null;
      this.context = context ?? null;
      this.initial = initial ?? null;
      this.editingId = editingId ?? null;
      this.openCount += 1;
      this.modal.show();
    },
    close() {
      this.modal.hide();
    },
    onSubmit(payload) {
      this.$emit('submit', {
        ...payload,
        snippetId: this.snippetId,
        hash: this.hash,
        from: this.from,
        context: this.context,
        editingId: this.editingId
      });
      this.close();
    }
  }
};
</script>

<style>
#snippet-editor-modal .modal-dialog {
  max-width: 1200px;
}
#snippet-editor-modal .modal-body {
  padding-top: 0;
}
</style>
