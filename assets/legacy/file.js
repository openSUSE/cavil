import CodeMirror from 'codemirror';

export function setupCodeMirrorForFile() {
  window.cavil.myCodeMirror = CodeMirror.fromTextArea(document.getElementById('file'), {theme: 'neo'});
}
