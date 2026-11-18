# External music in 0.57.2

## Use

1. Open Home > Music sources. Install Spotify Web for catalog search and either
   Tidal, Qobuz or YouTube Music for audio, or use those sources directly for both. Packages are
   downloaded from pinned Mornye registry locations and checksum-verified.
2. Choose the audio source for Spotify. When search, playback or an import needs
   verification, its browser opens directly over the current screen. Complete
   verification to resume the action automatically. Concurrent requests share
   one browser; a cancelled or repeatedly rejected attempt does not reopen it.
   If the browser does not return automatically, copy the verification link/code,
   close the browser and use the paste dialog (also available as Paste
   verification on the provider card). A bare `grant=...` is supported. Codes
   expire quickly; close an expired attempt and retry the action. Pasting does not
   start a new challenge or change the chosen provider.
   Configure exposes the package's settings, including optional HTTPS endpoints.
3. The floating Search title bar is the text field, leaving more space for
   discovery and results. Tap the Online indicator to add online results
   alongside library matches; tap again to hide only the online results. The
   icon and label are gray when off and accent-colored when on, with no pill,
   background, border or checkmark. Keyboard focus is shown with an underline.
   Hold it to choose a source from an anchored menu (right-click or Shift+F10 on
   Windows; an accessible source-selection action is also available). There is
   no separate source-selection field in unified search. Switching sources only
   refreshes online results. Online requests only run for a nonempty query while
   Online is enabled. Discovery remains visible when the query is empty.
   All/Albums/Songs filters apply across the displayed library and online
   sections; artists currently come from the library. Combined All results show
   a library preview with Show all library matches for expansion and pagination.
   Search songs/albums/playlists or paste a public music link.
   Spotify, Tidal and Qobuz links require their matching source. YouTube Music
   accepts regular youtube.com/watch and youtu.be links, Shorts/live/embed video
   links, public playlist links and Music browse/album links. A video link with
   both `v` and `list` opens that video; a playlist link opens the collection.
   Private playlists and other providers' shortened share links are unsupported.
4. Open the collection and play it through the shared queue. Playlist order and
   repeat entries are retained. Each song has its own download control; the
   collection download imports one copy of each distinct recording.
5. Configure Home > Remote folder and choose a destination. Downloads in search,
   collection view and Now Playing use that saved folder and MP3 320 conversion.

Monochrome remains available as an optional built-in source. If enabled, it can
be selected alongside installed extensions in the Online source picker.

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

## Extension runtime and playback

The supported packages are Spotify Web 1.10.6, Tidal Web 1.2.14,
Qobuz Web 1.2.27 and YouTube Music 2.4.7. This is a reviewed subset of the Mornye JavaScript ecosystem;
arbitrary extension installation and automatic package updates are not exposed.
The native host is pinned to Mornye 5.3.1's runtime and retains its feature gates,
network permissions, encrypted extension storage, signed sessions, cancellation
and temporary file grants. Hyperstream's app version remains independent.

The Dart adapter runs native calls in worker isolates. Its FFmpegKit command
pump supports extension media preparation. Spotify recordings are matched by the
chosen audio extension using ISRC, title, artist and duration. Failure to find a
match stops that request; this version does not silently switch audio providers.
The host preflights signed sessions before matching, streaming or downloading.
Verification failures retain the audio provider's identity even when the queue
fails before its first song loads. Successful verification resumes that song;
pause, queue changes and account changes prevent an old callback from restarting
playback. Imports release transfer resources before verification and retry only
the unconfirmed song, with a fresh background grant. A screen-off request waits
until the app is foregrounded before presenting its browser.

Playback queue entries contain stable source identities. A per-launch loopback
listener resolves audio when the native player requests it, forwards range
requests for seeking, and retries URL resolution once after an expired-link
response. Segmented responses use the extension downloader and may wait for
media preparation before playback begins. Prepared audio is temporary; app-side
stream resolution is not a persistent offline library.

YouTube searches use YouTube Music's catalog; this is not general YouTube video
search. Pasted videos keep their exact upload ID, uploader, title and available
thumbnail/duration. Native playback prefers M4A and forwards only the resolver's
public User-Agent, Origin and Referer headers. If a direct link remains blocked,
the package downloader tries its supported paths. Opus/WebM/Ogg playback copies
are converted to AAC for the native players, so fallback playback may take longer
to start. Imports convert the original downloaded audio directly to MP3 320;
that conversion does not improve the source's original fidelity. There is no
signed-session Verify button for YouTube; optional token settings use Configure.

YouTube collection pagination retains repeated uploads and fails if a page is
missing or the continuation chain loops/exceeds its bound. A failed page is not
silently treated as a complete downloadable playlist.

Installed packages, the host's encrypted store and temporary media live in app
storage. The encryption key and source selection use the existing protected
device store. Remote-folder and Navidrome credentials are never passed into an
extension. Its file grant covers one private staging directory; Hyperstream
alone publishes the validated MP3 to SMB.

Build details, source revisions, licensing and replacement instructions:
[native host](../apps/client/packages/mornye_host/UPSTREAM.md).

Live checks returned Spotify, Tidal and YouTube metadata, resolved a direct
YouTube M4A URL, and reached Qobuz's verification requirement.
End-to-end gateway verification, provider audio, actual iPhone
playback and remote delivery still need user acceptance. Service availability is
controlled by the provider and gateway. Durable import recovery, automatic
fallback, additional extensions and library-index confirmation remain future work.

## Existing shared import pipeline

`MusicProvider` defines search, album lookup, stream resolution and download.
`MonochromeProvider` implements the tracks API. `SourceReference` identifies the
provider/endpoint and recording in the shared track model. `SourceImports` owns
sequential batch delivery and uses `AudioFileShare`, `Mp3Converter` and
`RemoteTransfer` for download, processing and SMB publication.

The original built-in Monochrome adapter is retained alongside the new host.

The adapter follows the observed [Monochrome tracks API](https://github.com/monochrome-music/monochrome/blob/e677a8fd65ea53aeb7db51911120b7b3529ce058/js/tracks-api.js).
Future extension work draws on the [Mornye extension registry](https://github.com/mornyeapp/Mornye-Extension).

## Research preceding the 0.56.0 implementation

The user identifies Mornye as their current acquisition workflow and reports
stability problems with Monochrome. Prioritize Mornye-compatible extensions for
the next implementation milestone. The following review checked Mornye revision
`45df9860661e9c4e731ef26a60c44b2b5d8cf125` and its registry revision
`e9d2499688f77d8cbc224c1c1a1fe2ccfdb94555` on November 16, 2026.

The registry already supplies package locations, versions and SHA-256 digests.
Its JavaScript catalog includes the providers below. Hyperstream can discover
them through that registry. The user can choose providers within the app once
the extension host is implemented. [Registry](https://github.com/mornyeapp/Mornye-Extension/blob/e9d2499688f77d8cbc224c1c1a1fe2ccfdb94555/registry.json)

| Extension | Reviewed version | Declared role |
| --- | --- | --- |
| Spotify Web | 1.10.6 | Catalog metadata |
| Apple Music | 1.4.17 | Catalog metadata and lyrics |
| Tidal Web | 1.2.14 | Catalog metadata and downloads |
| Qobuz Web | 1.2.27 | Catalog metadata and downloads |
| Amazon Music | 2.3.19 | Catalog metadata and downloads |
| Deezer | 1.3.11 | Catalog metadata and downloads |
| SoundCloud | 1.0.15 | Catalog metadata and downloads |
| YouTube Music | 2.4.7 | Catalog metadata and downloads |

Mornye runs extension JavaScript in QuickJS through its Rust backend. The host
implements networking, per-extension storage, file operations, conversion,
authentication and session APIs. Hyperstream needs a tested host contract for
the selected packages. [Runtime](https://github.com/mornyeapp/Mornye/blob/45df9860661e9c4e731ef26a60c44b2b5d8cf125/rust_backend/crates/extensions/src/runtime/vm.rs),
[extension API](https://mornye.com/docs)

Catalog selection and audio acquisition have separate priorities. Mornye checks
recording identity during cross-provider matching and uses the selected provider,
availability, health and failure type when considering fallback. Its catalog
metadata can therefore originate from a different service than the audio.
[Download orchestration](https://github.com/mornyeapp/Mornye/blob/45df9860661e9c4e731ef26a60c44b2b5d8cf125/rust_backend/crates/extensions/src/backend/downloads.rs),
[identity validation](https://github.com/mornyeapp/Mornye/blob/45df9860661e9c4e731ef26a60c44b2b5d8cf125/rust_backend/crates/extensions/src/backend/downloads/matching.rs)

The reviewed Amazon, Tidal, Qobuz and Deezer packages declare signed sessions
against the same gateway. Implement the host's browser verification, callback,
grant exchange and protected session storage before claiming compatibility.
Hyperstream access to that gateway still requires live verification. Tidal and
Qobuz also expose optional custom download endpoints in their manifests.
[Amazon manifest](https://github.com/mornyeapp/Mornye-Extension/blob/e9d2499688f77d8cbc224c1c1a1fe2ccfdb94555/sources/amazon/manifest.json),
[Tidal manifest](https://github.com/mornyeapp/Mornye-Extension/blob/e9d2499688f77d8cbc224c1c1a1fe2ccfdb94555/sources/tidal-web/manifest.json),
[Qobuz manifest](https://github.com/mornyeapp/Mornye-Extension/blob/e9d2499688f77d8cbc224c1c1a1fe2ccfdb94555/sources/qobuz-web/manifest.json),
[Deezer manifest](https://github.com/mornyeapp/Mornye-Extension/blob/e9d2499688f77d8cbc224c1c1a1fe2ccfdb94555/sources/deezer/manifest.json)

Streaming needs an explicit compatibility check. Some packages implement the
file-download contract and return no value from `getDownloadUrl`. Replace the
current synchronous `streamUri` assumption with asynchronous provider resolution
that can carry headers, expiry and supported stream formats. Test each provider's
playback path, then connect its acquisition output to MP3 conversion and SMB
delivery. [Amazon download contract](https://github.com/mornyeapp/Mornye-Extension/blob/e9d2499688f77d8cbc224c1c1a1fe2ccfdb94555/sources/amazon/index.js)

The next implementation sequence is registry/package management, the required
JavaScript host APIs and verification flow, catalog/acquisition selection with
strict recording matching, then shared-player streaming and remote import
acceptance. Endpoint uptime and full package compatibility remain unverified.

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
