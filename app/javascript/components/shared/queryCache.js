import { QueryCache } from 'react-query';
import { isNumeric } from '@utils';

const { api_geo_url, api_adresse_url } = gon.autocomplete || {};

export const queryCache = new QueryCache({
  defaultConfig: {
    queries: {
      queryFn: defaultQueryFn
    }
  }
});

function buildURL(scope, term) {
  if (scope === 'adresse') {
    return `${api_adresse_url}/search?q=${term}&limit=5`;
  } else if (isNumeric(term)) {
    const code = term.padStart(2, '0');
    return `${api_geo_url}/${scope}?code=${code}&limit=5`;
  }
  return `${api_geo_url}/${scope}?nom=${term}&limit=5`;
}

function buildOptions() {
  if (window.AbortController) {
    const controller = new AbortController();
    const signal = controller.signal;
    return [{ signal }, controller];
  }
  return [{}, null];
}

async function defaultQueryFn(scope, term) {
  const url = buildURL(scope, term);
  const [options, controller] = buildOptions();
  const promise = fetch(url, options).then((response) => response.json());
  promise.cancel = () => controller && controller.abort();
  return promise;
}