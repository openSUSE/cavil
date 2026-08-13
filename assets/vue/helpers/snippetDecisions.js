import UserAgent from '@mojojs/user-agent';

// A file only gets an id once something matched in it, so one that matched nothing is addressed by path.
// Shared with the link the button carries, so the two can never disagree about where a range lives.
export function snippetRangeUrl({fileId, packageId, filePath, startLine, endLine, from, hash}) {
  const qs = new URLSearchParams({from});
  if (hash) qs.set('hash', hash);
  if (fileId > 0) return `/snippets/from_file/${fileId}/${startLine}/${endLine}?${qs.toString()}`;
  qs.set('start', startLine);
  qs.set('end', endLine);
  return `/snippets/from_path/${packageId}/${encodeURI(filePath)}?${qs.toString()}`;
}

export async function resolveSnippetFromFile(range) {
  const ua = new UserAgent({baseURL: window.location.href});
  const res = await ua.get(snippetRangeUrl(range), {
    headers: {Accept: 'application/json'}
  });
  if (!res.isSuccess) throw new Error(`Could not load snippet (HTTP ${res.statusCode})`);
  return await res.json();
}

// "report" names the package whose report these decisions were made against, so the server can refuse a
// batch that raced a rebuild of exactly that report. Pages that are not showing a report leave it out.
export async function submitSnippetDecisions(actions, {report = null} = {}) {
  const ua = new UserAgent({baseURL: window.location.href});
  const res = await ua.post('/snippet/batch_decision', {
    json: report === null ? {actions} : {actions, report},
    headers: {Accept: 'application/json'}
  });
  let data = null;
  try {
    data = await res.json();
  } catch (e) {
    // Handled by callers from the response status/data shape.
  }
  return {res, data, results: data && Array.isArray(data.results) ? data.results : []};
}
