// Adapter for the exact packages in catalog.json. Archives stay unmodified.
function hyperstreamSoundCloudCollection(id) {
  var data = scGet('playlists/' + id + '?representation=full');
  var info = formatPlaylistOrAlbum(data);
  var entries = data && data.tracks;
  if (!info || !Array.isArray(entries) || entries.length > 10000 ||
      (typeof data.track_count === 'number' && data.track_count !== entries.length))
    throw new Error('SoundCloud collection is incomplete');
  var full = {}, missing = [];
  for (var i = 0; i < entries.length; i++) {
    var entry = entries[i];
    if (!entry || !/^\d+$/.test(String(entry.id)))
      throw new Error('SoundCloud collection contains an unavailable entry');
    if (entry.title) full[entry.id] = entry;
    else if (missing.indexOf(entry.id) < 0) missing.push(entry.id);
  }
  // Hydrate abbreviated records, then reconstruct the original positions.
  // Never append the hydrated tail or silently swallow a missing batch.
  for (var start = 0; start < missing.length; start += 50) {
    var batch = scGet('tracks?ids=' + missing.slice(start, start + 50).join(','));
    if (!Array.isArray(batch)) throw new Error('SoundCloud collection page unavailable');
    for (var b = 0; b < batch.length; b++) {
      if (batch[b] && batch[b].title) full[batch[b].id] = batch[b];
    }
  }
  var tracks = entries.map(function(entry, index) {
    var raw = full[entry.id];
    if (!raw) throw new Error('SoundCloud collection contains an unavailable entry');
    trackCacheSet(raw.id, raw);
    var track = formatTrack(raw);
    if (!track) throw new Error('SoundCloud collection contains an invalid entry');
    track.track_number = index + 1;
    if (info.item_type === 'album') {
      track.album_id = String(data.id);
      track.album_name = info.name;
    }
    return track;
  });
  info.total_tracks = tracks.length;
  return {info:info, tracks:tracks};
}

function hyperstreamSoundCloudUnavailable() {
  return {success:false, error_code:'track_unavailable'};
}

function hyperstreamSoundCloudResolve(id) {
  // Refresh track authorization on each resolution, including expired-URL retry.
  var track = scGet('tracks/' + id);
  trackCacheSet(id, track);
  if (!isFullPlayableTrack(track)) return hyperstreamSoundCloudUnavailable();
  var candidates = rankTranscodings((track.media && track.media.transcodings) || [], 'aac');
  if (!candidates.length) return hyperstreamSoundCloudUnavailable();
  for (var i = 0; i < candidates.length; i++) {
    var candidate = candidates[i], format = transcodingFormat(candidate);
    if (candidate.format.protocol !== 'progressive' ||
        (format !== 'm4a' && format !== 'mp3')) continue;
    try {
      var url = resolveStreamURL(candidate, track);
      return {url:url, format:format, prepareOnFailure:true,
        headers:{'User-Agent':userAgentForURL(url)}};
    } catch (_) { /* The reviewed downloader can prepare another full stream. */ }
  }
  // The existing preparation path joins HLS locally, retaining duration checks,
  // cancellation and file grants. Never pass a remote manifest to FFmpeg/player.
  return {prepare:true};
}

function hyperstreamYouTubeCollection(id, playlist) {
  var browse = playlist && !/^(VL|RDCLAK5uy_)/.test(id) ? 'VL' + id : id;
  var data = fetchJSONSync('https://music.youtube.com/youtubei/v1/browse?alt=json', {
    method:'POST',
    headers:{'Content-Type':'application/json', 'User-Agent':getRandomUserAgent(),
      'x-youtube-client-name':'WEB_REMIX', 'x-youtube-client-version':CONFIG.clientVersion},
    body:JSON.stringify({context:{client:{clientName:'WEB_REMIX', clientVersion:CONFIG.clientVersion}}, browseId:browse})
  });
  var result = data && parseBrowseResponse(data, browse);
  if (!result || !result.tracks) throw new Error('YouTube collection unavailable');
  var token = result._continuationToken;
  var firstPageCount = result.tracks.length;
  var seen = {};
  var page = 0;
  while (token) {
    if (seen[token] || page++ >= MAX_CONTINUATION_PAGES)
      throw new Error('YouTube collection pagination incomplete');
    seen[token] = true;
    var next = fetchContinuationSync(token);
    if (!next) throw new Error('YouTube collection page unavailable');
    var parsed = parseContinuationResponse(next);
    if (!parsed || !parsed.tracks || !parsed.tracks.length)
      throw new Error('YouTube collection page incomplete');
    for (var i = 0; i < parsed.tracks.length; i++) {
      var node = parsed.tracks[i];
      var track = parseItemExtended(node.musicResponsiveListItemRenderer || node.playlistPanelVideoRenderer || node);
      if (!track) throw new Error('YouTube collection contains an unavailable entry');
      applyBrowseCollectionMetadata(track, result.album, playlist);
      var sanitized = sanitizeTrackBeforeReturn(track);
      if (!sanitized) throw new Error('YouTube collection contains an unavailable entry');
      // Repeated uploads are playlist entries, not pagination duplicates.
      result.tracks.push(sanitized);
    }
    token = parsed.continuationToken;
  }
  var album = result.album || {};
  var expected = Number(album.total_tracks) || 0;
  if (expected > firstPageCount && expected !== result.tracks.length)
    throw new Error('YouTube collection did not return every entry');
  return {id:id, name:result.name || album.name || (playlist ? 'YouTube playlist' : 'YouTube album'),
    artists:album.artists || '', cover_url:result.cover_url || album.cover_url || null,
    total_tracks:result.tracks.length, tracks:result.tracks, type:playlist ? 'playlist' : 'album'};
}
var hyperstreamRegister = registerExtension;
registerExtension = function(extension) {
  var soundcloud = typeof isFullPlayableTrack === 'function' &&
    typeof rankTranscodings === 'function' && typeof fetchTrackData === 'function';
  if (soundcloud) {
    var originalFormatTrack = formatTrack;
    formatTrack = function(raw) {
      var formatted = originalFormatTrack(raw);
      if (formatted) {
        formatted.is_playable = isFullPlayableTrack(raw);
        if (raw.media && Array.isArray(raw.media.transcodings) &&
            !rankTranscodings(raw.media.transcodings, 'aac').length)
          formatted.is_playable = false;
      }
      return formatted;
    };
    fetchPlaylistOrAlbum = hyperstreamSoundCloudCollection;
  }
  if (typeof fetchVideoMetadataSync === 'function') {
    // handleUrl returns a temporary "Loading..." row while it fetches in the
    // background. Resolve pasted videos synchronously and retain upload metadata.
    extension.getTrack = function(id) {
      var track = fetchVideoMetadataSync(id);
      return track ? sanitizeTrackBeforeReturn(track) : null;
    };
    extension.getPlaylist = function(id) { return hyperstreamYouTubeCollection(id, true); };
    extension.getAlbum = function(id) { return hyperstreamYouTubeCollection(id, false); };
  }
  extension.hyperstreamCompleteGrant = function() { return session.completeGrant(); };
  extension.hyperstreamDownload = function(id, quality, output) {
    if (soundcloud && !isFullPlayableTrack(fetchTrackData(id)))
      return hyperstreamSoundCloudUnavailable();
    return extension.download(id, quality, output, function() {}, {});
  };
  extension.hyperstreamResolve = function(id, quality) {
    if (soundcloud) return hyperstreamSoundCloudResolve(id);
    if (typeof requestInnerTubeAudioDownload === 'function') {
      // Keep the chosen upload. M4A can stream through both native players;
      // Opus and failed direct URLs use the package's downloader/preparation.
      try {
        var youtube = requestInnerTubeAudioDownload(id);
        var candidates = [youtube].concat(youtube.alternatives || []);
        for (var i = 0; i < candidates.length; i++) {
          var audio = candidates[i];
          if (audio.extension === '.m4a' && audio.url && waitUntilAvailable(audio)) {
            return {
              url:audio.url, format:'m4a', prepareOnFailure:true,
              headers:{'User-Agent':audio.ua || getRandomUserAgent(),
                'Referer':'https://www.youtube.com/watch?v=' + id,
                'Origin':'https://www.youtube.com'}
            };
          }
        }
      } catch (_) { /* The downloader retains the package's own fallbacks. */ }
      return {prepare:true};
    }
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
