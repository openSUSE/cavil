import CodeMirror from 'codemirror';

export function setupCodeMirrorForFile() {
  window.legacy.myCodeMirror = CodeMirror.fromTextArea(document.getElementById('file'), {theme: 'neo'});
}
