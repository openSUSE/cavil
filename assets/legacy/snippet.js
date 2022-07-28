import CodeMirror from 'codemirror';

export function setupCodeMirrorForSnippet(line) {
  const cm = CodeMirror.fromTextArea(document.getElementById('file'), {
    theme: 'neo',
    lineNumbers: true,
    firstLineNumber: line
  });
  cm.on('gutterClick', (cm, n) => {
    const info = cm.lineInfo(n);
    if (info.bgClass.includes('found-pattern')) {
      matches = info.bgClass.match(/pattern-(\d+)/);
      window.location.href = `/licenses/edit_pattern/${matches[1]}`;
    }
  });

  window.legacy.myCodeMirror = cm;
}
