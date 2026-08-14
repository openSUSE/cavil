<template>
  <div class="comment-editor" :class="{'is-interactive': isInteractive}">
    <div class="comment-editor-header">
      <span class="comment-editor-label" :id="labelId">{{ label }}</span>
      <div class="comment-editor-tools">
        <slot name="actions"></slot>
        <button
          type="button"
          class="comment-editor-tool-btn"
          data-action="undo"
          :disabled="!canUndo || readOnly"
          title="Undo"
          aria-label="Undo"
          @click="undoEdit"
        >
          <i class="fa-solid fa-rotate-left"></i>
        </button>
        <button
          type="button"
          class="comment-editor-tool-btn"
          data-action="redo"
          :disabled="!canRedo || readOnly"
          title="Redo"
          aria-label="Redo"
          @click="redoEdit"
        >
          <i class="fa-solid fa-rotate-right"></i>
        </button>
      </div>
    </div>
    <div ref="editorHost" class="comment-editor-host"></div>
    <div v-if="isInteractive && placeholderCount > 0" class="comment-editor-hints">
      Click a <code>[PLACEHOLDER]</code> to replace it &middot; Tab jumps to the next &middot; Esc leaves the editor
    </div>
  </div>
</template>

<script>
import {
  findPlaceholders,
  nextPlaceholder,
  placeholderAt,
  placeholderHighlighter,
  previousPlaceholder
} from '../helpers/placeholders.js';
import {defaultKeymap, history, historyKeymap, redo, redoDepth, undo, undoDepth} from '@codemirror/commands';
import {EditorState, Prec} from '@codemirror/state';
import {EditorView, keymap, placeholder as emptyDocHint} from '@codemirror/view';
import {markRaw} from 'vue';

let nextLabelId = 1;

export default {
  name: 'CommentEditor',
  props: {
    // Not the [PLACEHOLDER] tokens, this is the hint shown while the document is empty
    placeholder: {type: String, default: ''},
    label: {type: String, default: 'Comment'},
    // Click-to-fill and tab jumps; turned off where placeholders are being authored rather than filled in
    interactive: {type: Boolean, default: true},
    modelValue: {type: String, default: ''},
    readOnly: {type: Boolean, default: false}
  },
  emits: ['update:modelValue'],
  data() {
    return {
      canRedo: false,
      canUndo: false,
      editor: null,
      insertingTemplate: false,
      labelId: `comment-editor-label-${nextLabelId++}`,
      placeholderCount: 0,
      suppressEmit: false,
      // Where the last inserted template body starts, or null once the reviewer has edited the document
      templateFrom: null
    };
  },
  computed: {
    isInteractive() {
      return this.interactive && !this.readOnly;
    }
  },
  mounted() {
    const theme = EditorView.theme({
      '&': {fontSize: '14px'},
      '.cm-content': {minHeight: '12rem', padding: '0.75rem'},
      '.cm-scroller': {fontFamily: 'monospace, monospace', lineHeight: '1.45', overflow: 'auto'},
      '.cm-line': {padding: '0'}
    });

    const extensions = [
      placeholderHighlighter(),
      EditorView.lineWrapping,
      EditorView.contentAttributes.of({'aria-labelledby': this.labelId}),

      // A bare CodeMirror has no undo at all, unlike the textarea this replaces
      history(),
      Prec.high(
        keymap.of([
          {key: 'Tab', run: view => this.jumpPlaceholder(view, true)},
          {key: 'Shift-Tab', run: view => this.jumpPlaceholder(view, false)},
          {key: 'Escape', run: view => this.leaveEditor(view)}
        ])
      ),
      keymap.of([...historyKeymap, ...defaultKeymap]),
      EditorView.domEventHandlers({mousedown: (event, view) => this.fillPlaceholder(event, view)}),
      EditorView.updateListener.of(update => this.onUpdate(update)),
      theme
    ];
    if (this.placeholder !== '') extensions.push(emptyDocHint(this.placeholder));
    if (this.readOnly) extensions.push(EditorState.readOnly.of(true), EditorView.editable.of(false));

    const state = EditorState.create({doc: this.modelValue, extensions});

    // Not reactive: commands like undo() destructure the view and build a transaction from its state, and
    // a transaction created from a reactive proxy of the state is rejected as not starting from it
    this.editor = markRaw(new EditorView({parent: this.$refs.editorHost, state}));
    this.editor.dom.cmView = this.editor;
    this.placeholderCount = findPlaceholders(this.modelValue).length;
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
  },
  methods: {
    onUpdate(update) {
      this.canRedo = redoDepth(update.state) > 0;
      this.canUndo = undoDepth(update.state) > 0;
      if (!update.docChanged) return;

      // Once the reviewer has edited anything the template is their text, not a pick to be swapped out
      if (!this.insertingTemplate) this.templateFrom = null;
      const text = update.state.doc.toString();
      this.placeholderCount = findPlaceholders(text).length;
      if (!this.suppressEmit) this.$emit('update:modelValue', text);
    },
    redoEdit() {
      if (!this.editor) return;
      redo(this.editor);
      this.editor.focus();
    },
    undoEdit() {
      if (!this.editor) return;
      undo(this.editor);
      this.editor.focus();
    },
    fillPlaceholder(event, view) {
      if (!this.isInteractive) return false;
      const pos = view.posAtCoords({x: event.clientX, y: event.clientY});
      if (pos === null) return false;
      const found = placeholderAt(view.state.doc.toString(), pos);
      if (found === null) return false;

      // Handled, so CodeMirror does not immediately collapse the range we just selected
      view.dispatch({selection: {anchor: found.from, head: found.to}});
      view.focus();
      return true;
    },
    // Returning false leaves Tab unhandled, so the browser moves focus as usual. That is the only way out
    // for keyboard users, which is also why there is no wrap around from the last placeholder to the first.
    jumpPlaceholder(view, forward) {
      if (!this.isInteractive) return false;
      const text = view.state.doc.toString();
      const selection = view.state.selection.main;
      const found = forward ? nextPlaceholder(text, selection.to) : previousPlaceholder(text, selection.from);
      if (found === null) return false;
      view.dispatch({selection: {anchor: found.from, head: found.to}, scrollIntoView: true});
      return true;
    },
    leaveEditor(view) {
      view.contentDOM.blur();
      return true;
    },
    // One transaction, so the insert is a single undo step and the selection can be placed in the same go
    insertTemplate(body) {
      if (!this.editor) return;
      const current = this.editor.state.doc.toString();

      // Picking again without typing in between is a correction of the first pick, so that untouched
      // body is swapped out. Anything the reviewer wrote themselves is kept and appended to.
      const keep = this.templateFrom === null ? current : current.slice(0, this.templateFrom);
      const trimmed = keep.replace(/\s+$/, '');
      const prefix = trimmed === '' ? '' : trimmed + '\n\n';
      const insert = prefix + body;

      const found = findPlaceholders(body)[0] ?? null;
      const selection =
        found === null ? {anchor: insert.length} : {anchor: prefix.length + found.from, head: prefix.length + found.to};

      this.insertingTemplate = true;
      this.editor.dispatch({changes: {from: 0, to: current.length, insert}, selection, scrollIntoView: true});
      this.insertingTemplate = false;
      this.templateFrom = prefix.length;
      this.editor.focus();
    }
  }
};
</script>

<style scoped>
.comment-editor {
  background: var(--cavil-canvas);
  border: 1px solid var(--cavil-border);
  border-radius: 6px;
  overflow: hidden;
}
.comment-editor:focus-within {
  border-color: var(--cavil-accent);
  box-shadow: 0 0 0 3px rgba(var(--cavil-accent-rgb), 0.18);
}
.comment-editor-header {
  align-items: center;
  background: var(--cavil-canvas-subtle);
  border-bottom: 1px solid var(--cavil-border);
  color: var(--cavil-fg);
  display: flex;
  font-size: 13px;
  font-weight: 600;
  gap: 0.5rem;
  min-height: 2.25rem;
  padding: 0.45rem 0.75rem;
}
.comment-editor-label {
  flex: 1;
}
.comment-editor-tools {
  align-items: center;
  display: inline-flex;
  gap: 0.35rem;
}
.comment-editor-tool-btn {
  align-items: center;
  background: var(--cavil-surface-raised);
  border: 1px solid var(--cavil-border);
  border-radius: 6px;
  box-shadow: 0 1px 2px rgba(var(--cavil-shadow-alt-rgb), 0.08);
  color: var(--cavil-fg);
  cursor: pointer;
  display: inline-flex;
  font-size: 13px;
  height: 28px;
  justify-content: center;
  padding: 0;
  transition:
    background-color 0.15s,
    box-shadow 0.15s,
    color 0.15s;
  width: 28px;
}
.comment-editor-tool-btn:hover:not(:disabled) {
  background: var(--cavil-canvas);
  box-shadow: 0 2px 4px rgba(var(--cavil-shadow-alt-rgb), 0.12);
  color: var(--cavil-accent);
}
.comment-editor-tool-btn:focus {
  border-color: var(--cavil-accent);
  box-shadow: 0 0 0 3px rgba(var(--cavil-accent-rgb), 0.3);
  color: var(--cavil-accent);
  outline: none;
}
.comment-editor-tool-btn:disabled {
  cursor: not-allowed;
  opacity: 0.5;
}
.comment-editor-hints {
  background: var(--cavil-canvas-subtle);
  border-top: 1px solid var(--cavil-border);
  color: var(--cavil-fg-muted);
  font-size: 12px;
  padding: 0.35rem 0.75rem;
}
.comment-editor-hints code {
  color: var(--cavil-fg-muted);
}
.comment-editor-host :deep(.cm-editor) {
  height: auto;
  max-height: 60vh;
}
.comment-editor-host :deep(.cm-editor.cm-focused) {
  outline: none;
}
.comment-editor-host :deep(.cavil-placeholder) {
  background: var(--cavil-accent-bg);
  border-radius: 3px;
  box-shadow: inset 0 0 0 1px var(--cavil-accent-border);
  color: var(--cavil-accent-strong);
}
.comment-editor.is-interactive .comment-editor-host :deep(.cavil-placeholder) {
  cursor: pointer;
}
</style>
