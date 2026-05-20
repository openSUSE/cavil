import {EditorState} from '@codemirror/state';
import {EditorView, lineNumbers} from '@codemirror/view';

export function setupCodeMirrorForFile() {
  const textarea = document.getElementById('file');
  if (!textarea) return;

  const host = document.createElement('div');
  host.className = 'cavil-file-viewer';
  textarea.parentNode.insertBefore(host, textarea);
  textarea.style.display = 'none';

  const view = new EditorView({
    parent: host,
    state: EditorState.create({
      doc: textarea.value,
      extensions: [lineNumbers(), EditorView.editable.of(false), EditorState.readOnly.of(true)]
    })
  });

  window.cavil.myCodeMirror = view;
}
