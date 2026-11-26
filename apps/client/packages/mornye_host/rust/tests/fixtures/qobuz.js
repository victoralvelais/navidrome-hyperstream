function fetchProviderDownloadInfo(provider, id, quality) {
  attempts.push({provider:provider, id:id, quality:quality});
  if (id === 'verify') {
    throw new Error('E_SESSION_VERIFICATION_REQUIRED');
  }
  if (provider === 'second' && id !== 'unavailable') {
    return {directURL:'https://example.test/' + id + '.flac'};
  }
  var error = new Error(provider === 'first' ? 'Candidate unavailable' : 'Candidate timed out');
  error.code = provider === 'first' ? 'fixture_unavailable' : 'fixture_timeout';
  error.retryMode = provider === 'first' ? 'none' : 'retry';
  throw error;
}

var originalFetch = fetchProviderDownloadInfo;
var attempts = [];

function isVerificationRequiredError(error) {
  return error && error.message === 'E_SESSION_VERIFICATION_REQUIRED';
}

function resolveDownloadInfo(id, quality, options) {
  var providers = ['first', 'second'];
  var lastError;
  for (var i = 0; i < providers.length; i++) {
    try {
      return fetchProviderDownloadInfo(providers[i], id, quality, options);
    } catch (error) {
      if (isVerificationRequiredError(error)) throw error;
      lastError = error;
    }
  }
  throw new Error('All audio providers failed: ' + lastError.message);
}

registerExtension({
  getTrack:function(id) {
    return {id:id, fetchRestored:fetchProviderDownloadInfo === originalFetch, attempts:attempts};
  }
});
