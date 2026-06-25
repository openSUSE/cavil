import UserAgent from '@mojojs/user-agent';

export async function resolveSnippetFromFile({fileId, startLine, endLine, from, hash}) {
  const qs = new URLSearchParams({from});
  if (hash) qs.set('hash', hash);
  const ua = new UserAgent({baseURL: window.location.href});
  const res = await ua.get(`/snippets/from_file/${fileId}/${startLine}/${endLine}?${qs.toString()}`, {
    headers: {Accept: 'application/json'}
  });
  if (!res.isSuccess) throw new Error(`Could not load snippet (HTTP ${res.statusCode})`);
  return await res.json();
}

export async function submitSnippetDecisions(actions) {
  const ua = new UserAgent({baseURL: window.location.href});
  const res = await ua.post('/snippet/batch_decision', {
    json: {actions},
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
