<template>
  <div class="pattern-codemirror">
    <div ref="editorHost" class="pattern-codemirror-host"></div>
  </div>
</template>

<script>
import {EditorState} from '@codemirror/state';
import {EditorView, lineNumbers} from '@codemirror/view';

export default {
  name: 'PatternCodeMirror',
  props: {
    modelValue: {type: String, default: ''}
  },
  emits: ['update:modelValue'],
  data() {
    return {editor: null, suppressEmit: false};
  },
  mounted() {
    const theme = EditorView.theme({
      '&': {fontSize: '13px'},
      '.cm-scroller': {fontFamily: 'monospace, monospace', overflow: 'auto'},
      '.cm-gutters': {
        backgroundColor: '#f6f8fa',
        color: '#6e7781',
        borderRight: '1px solid #d0d7de'
      },
      '.cm-lineNumbers .cm-gutterElement': {padding: '0 8px 0 6px'}
    });

    const state = EditorState.create({
      doc: this.modelValue,
      extensions: [
        lineNumbers(),
        EditorView.lineWrapping,
        theme,
        EditorView.updateListener.of(update => {
          if (!update.docChanged || this.suppressEmit) return;
          this.$emit('update:modelValue', update.state.doc.toString());
        })
      ]
    });

    this.editor = new EditorView({parent: this.$refs.editorHost, state});
    this.editor.dom.cmView = this.editor;
  },
  beforeUnmount() {
    if (this.editor) {
      this.editor.destroy();
      this.editor = null;
    }
  },
  watch: {
    modelValue(newVal) {
      if (!this.editor) return;
      const current = this.editor.state.doc.toString();
      if (current === newVal) return;
      this.suppressEmit = true;
      this.editor.dispatch({changes: {from: 0, to: current.length, insert: newVal}});
      this.suppressEmit = false;
    }
  }
};
</script>

<style scoped>
.pattern-codemirror-host {
  border: 1px solid #d0d7de;
  border-radius: 6px;
  overflow: hidden;
}
.pattern-codemirror-host :deep(.cm-editor) {
  height: auto;
  max-height: 70vh;
}
.pattern-codemirror-host :deep(.cm-editor.cm-focused) {
  outline: none;
}
</style>
