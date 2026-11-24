export function genParamWatchers(...names) {
  const watchers = {};

  for (const name of names) {
    watchers[`params.${name}`] = function (value) {
      setParam(name, value);
    };
  }

  return watchers;
}

export function getParams(defaults = {}) {
  const params = defaults;
  for (const [key, value] of new URLSearchParams(window.location.search)) {
    params[key] = typeof defaults[key] === 'boolean' ? value === 'true' : value;
  }
  return params;
}

export function setParam(name, value) {
  const url = new URL(window.location);
  const params = new URLSearchParams(window.location.search);
  params.set(name, value);
  url.search = params.toString();
  window.history.replaceState({}, '', url);
}
