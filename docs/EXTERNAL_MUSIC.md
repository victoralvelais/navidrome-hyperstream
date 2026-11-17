# External music in 0.55.0

## Use

1. Open Home, Music sources. Enable Monochrome and save the source. The default
   endpoint is `https://tracks.monochrome.st`. A compatible HTTPS endpoint can be
   saved locally, including a reverse-proxy path prefix.
2. Open Search, Online. Search for a song or album. Tap a song or an album's Play
   button to use Hyperstream's shared queue and playback controls.
3. Configure Home, Remote folder and select a destination. Download buttons in
   online search, album view and Now Playing send the selected recordings there.

Songs download into a private temporary directory, convert with LAME to stereo
44.1 kHz MP3 at 320 kbps, and undergo codec, bitrate and duration validation.
Title, artist, album, track/disc number, ISRC and available artwork are retained.
Publication uses the existing SMB temporary-file, size-check and rename flow.
Existing filenames get numbered alternatives. Temporary source and conversion
files are cleaned after each attempt. Navidrome indexes delivered files through
its configured library scan when the selected destination is in its music path.

## Transfer behavior

Album downloads run sequentially and continue independently of the initiating
page. Success produces the existing quiet completion notification or an in-app
message. A failure stops the album and exposes the remaining-song retry in Music
sources. Confirmed songs are omitted from that retry.

iOS quiet background time remains limited. If it expires, an explicit retry can
use iOS activity. Screen-off acceptance needs testing on a device. Force-quitting
ends the transfer and clears in-memory batch progress. An uncertain rename
acknowledgment requires checking the destination before starting another import.

Provider settings use the existing protected device storage. External artwork
uses an independent unauthenticated HTTP client. Playback stores catalog IDs and
public cover references, then resolves audio URLs through the configured source.
Navidrome scrobbling, favorites and server-playlist actions apply to library tracks.

## Architecture and next milestones

`MusicProvider` defines search, album lookup, stream resolution and download.
`MonochromeProvider` implements the tracks API. `SourceReference` identifies the
provider/endpoint and recording in the shared track model. `SourceImports` owns
sequential batch delivery and uses `AudioFileShare`, `Mp3Converter` and
`RemoteTransfer` for download, processing and SMB publication.

This release includes one built-in adapter. Mornye/SpotiFLAC extension packages,
provider account authentication, durable import recovery, source matching and
automatic Navidrome scan confirmation remain subsequent milestones. The public
endpoint's catalog and availability depend on its operator.

The adapter follows the observed [Monochrome tracks API](https://github.com/monochrome-music/monochrome/blob/e677a8fd65ea53aeb7db51911120b7b3529ce058/js/tracks-api.js).
Future extension work draws on the [Mornye extension registry](https://github.com/mornyeapp/Mornye-Extension).

## Verification

- Automated provider tests cover catalog parsing, incomplete albums, source IDs,
  protected settings, sanitized failures and partial-download rejection.
- Playback tests cover shared tempo/transport, restored external identities and
  isolation from Navidrome listening history. Widget tests exercise online search,
  album navigation and playback in light/dark themes with enlarged text.
- Import tests cover partial-album retry, uncertain publication, concurrent
  requests and account changes. Existing SMB tests cover collision-safe delivery.
- The Windows native integration check generates synthetic FLAC, converts it to
  MP3 320, and verifies duration, metadata and attached artwork. CI builds both
  platform packages with the pinned audio conversion dependency.

On an iPhone, verify external playback and seeking, lock-screen controls, tempo,
camera playback, individual/album transfers, metadata/artwork in Navidrome after
scanning, and quiet-timeout retry. Check the same folder before retrying any
publication reported as uncertain.

Native license texts ship in Open-source licenses. Windows also includes the
audio bundle's `licenses` directory beside the executable. The native bundle
versions and source references appear in those notices.
