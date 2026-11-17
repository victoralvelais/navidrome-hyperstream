// Adapter for the exact packages in catalog.json. Archives stay unmodified.
var hyperstreamRegister = registerExtension;
registerExtension = function(extension) {
  extension.hyperstreamCompleteGrant = function() { return session.completeGrant(); };
  extension.hyperstreamDownload = function(id, quality, output) {
    return extension.download(id, quality, output, function() {}, {});
  };
  extension.hyperstreamResolve = function(id, quality) {
    if (typeof resolveDownloadInfo === 'function') {
      var q = resolveDownloadInfo(id, quality || 'LOSSLESS', {});
      return {url:q.directURL, format:'flac'};
    }
    if (typeof fetchDownloadInfo === 'function') {
      var t = fetchDownloadInfo(id, quality || 'HIGH', {});
      return t.kind === 'direct'
        ? {url:t.directURL, format:inferOutputExtension(t, quality || 'HIGH').replace('.', '')}
        : {prepare:true};
    }
    throw new Error('This package has no Hyperstream streaming adapter');
  };
  hyperstreamRegister(extension);
};
