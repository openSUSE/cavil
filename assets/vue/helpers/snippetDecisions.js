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

// The checksum a licensed match must be ignored by, resolved server-side from the match's stored range so
// it matches what the indexer recomputes. No snippet occurrence is created (resolveSnippetFromFile would
// leave a file_snippets row and make the match look unresolved). Keyed by pattern id + a line the match
// covers, since the rendered range can differ from the stored one under overlaps.
export async function resolveMatchChecksum({fileId, pid, line}) {
  const ua = new UserAgent({baseURL: window.location.href});
  const res = await ua.get(`/snippets/match_checksum/${fileId}/${pid}/${line}`, {
    headers: {Accept: 'application/json'}
  });
  if (!res.isSuccess) throw new Error(`Could not compute checksum (HTTP ${res.statusCode})`);
  return await res.json();
}

// A staged create-ignore, shared by every host so the shape stays in sync. startLine/endLine carry the
// displayed match range (so the line marker attaches via FileSource's actionsForLine) while hash is the
// server-resolved checksum of the match's stored range.
export function ignorePendingAction({id, meta, hash}) {
  const from = meta.from ?? null;
  return {
    id,
    snippetId: null,
    fileId: meta.fileId,
    startLine: meta.startLine,
    endLine: meta.endLine,
    hash,
    from,
    filePath: meta.filePath ?? null,
    action: 'create-ignore',
    formData: {hash, from},
    license: '',
    locationLabel: `${meta.filePath ?? `file ${meta.fileId}`}:${meta.startLine}-${meta.endLine}`,
    state: 'pending',
    error: null
  };
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
