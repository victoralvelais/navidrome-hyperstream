// Synthetic package contract. No credentials, provider audio or network calls.
var fixtureCollection = '', cached = {};
function rawTrack(id) {
  return {id:String(id), title:'Upload ' + id, duration:120000,
    policy:id === '3' ? 'SNIP' : id === '4' ? 'BLOCK' : 'ALLOW',
    media:{transcodings:[
      {url:'https://example.test/hls', format:{protocol:'hls', mime_type:'audio/mp4'},
        snipped:id === '5'},
      ...(['1', '6'].includes(id) ? [{url:'https://example.test/audio',
        preset:id === '1' ? 'mp3_0_1' : 'mp3_0_128k',
        format:{protocol:'progressive', mime_type:'audio/mpeg'}}] : [])
    ]}};
}
function scGet(path) {
  if (path.indexOf('playlists/') === 0) {
    fixtureCollection = path.split('/')[1].split('?')[0];
    return {id:70, title:'Ordered set', track_count:fixtureCollection === 'count' ? 5 : 4,
      tracks:[{id:102}, rawTrack(101), {id:102}, {id:103}]};
  }
  if (path.indexOf('tracks?ids=') === 0) {
    if (fixtureCollection === 'failed') throw new Error('Page unavailable');
    // Upstream batch order is different; a record can be missing entirely.
    return fixtureCollection === 'missing' ? [rawTrack(103)] : [rawTrack(103), rawTrack(102)];
  }
  return rawTrack(path.split('/')[1]);
}
function trackCacheSet(id, track) { cached[id] = track; return track; }
function fetchTrackData(id) { return cached[id] || rawTrack(id); }
function formatTrack(raw) { return {id:String(raw.id), name:raw.title}; }
function formatPlaylistOrAlbum(raw) { return {id:String(raw.id), name:raw.title, item_type:'playlist'}; }
function fetchPlaylistOrAlbum() { throw new Error('Adapter must replace incomplete ordering'); }
function isFullPlayableTrack(t) { return t.policy !== 'SNIP' && t.policy !== 'BLOCK'; }
function rankTranscodings(ts) { return ts.filter(function(t) { return !t.snipped; }); }
function transcodingFormat(t) { return t.format.mime_type === 'audio/mp4' ? 'm4a' : 'mp3'; }
function resolveStreamURL(t) { return t.url; }
function userAgentForURL() { return 'Synthetic public client'; }
registerExtension({
  getTrack:function(id) { return formatTrack(fetchTrackData(id)); },
  getPlaylist:function(id) {
    var collection = fetchPlaylistOrAlbum(id);
    return {tracks:collection.tracks, total_tracks:collection.info.total_tracks};
  },
  download:function(id, quality, path, progress) {
    if (quality !== 'aac_160') throw new Error('Incorrect SoundCloud quality');
    progress(0.5);
    var result = file.write(path, 'synthetic audio ' + id);
    return {success:result.success, file_path:path};
  }
});
