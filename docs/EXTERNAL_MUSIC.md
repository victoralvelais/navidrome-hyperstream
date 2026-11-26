# External music

## Use

1. Open Home > Music sources. Install Spotify Web for catalog search and either
   Tidal, Qobuz, YouTube Music or SoundCloud for audio, or use those sources directly for both. Packages are
   downloaded from pinned Mornye registry locations and checksum-verified.
2. Choose the audio source for Spotify. When search, playback or an import needs
   verification, its browser opens directly over the current screen. All-source
   searches instead show a Verify action for each affected source, so successful
   results remain usable without opening several verification flows. Complete
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
   Online searches all enabled sources by default. Hold it to choose All sources
   or one source from an anchored menu (right-click or Shift+F10 on
   Windows; an accessible source-selection action is also available). There is
   no separate source-selection field in unified search. Switching sources only
   refreshes online results. This device-local preference is saved securely and
   is independent of the audio provider chosen for Spotify. Online requests only run for a nonempty query while
   Online is enabled. Discovery remains visible when the query is empty.
   All/Albums/Songs filters apply across the displayed library and online
   sections; artists currently come from the library. Combined All results show
   a library preview with Show all library matches for expansion and pagination.
   Search songs/albums/playlists or paste a public music link.
   In All sources mode, pasted links go only to the matching enabled source;
   unrelated sources are not queried. Spotify, Tidal and Qobuz links require their matching source. YouTube Music
   accepts regular youtube.com/watch and youtu.be links, Shorts/live/embed video
   links, public playlist links and Music browse/album links. A video link with
   both `v` and `list` opens that video; a playlist link opens the collection.
   SoundCloud supports public upload and `/creator/sets/name` album/playlist
   links, including mobile and `on.soundcloud.com` short links. Tracking query
   parameters are discarded. Profiles and private playlists are unsupported.
   Other providers' shortened share links remain unsupported.
4. Open the collection and play it through the shared queue. Playlist order and
   repeat entries are retained. Each song has its own download control; the
   collection download imports one copy of each distinct recording.
5. Configure Home > Remote folder and choose a destination. Downloads in search,
   collection view and Now Playing use that saved folder, preserving lossy audio
   and converting lossless audio to MP3 320.

Monochrome remains available as an optional built-in source. If enabled, it can
be selected alongside installed extensions in the Online source picker.

### Combined search and source badges

Songs and albums are each ranked across sources using title/artist matches,
query-word coverage and a smaller contribution from the provider's result order.
Exact matches rank ahead of loose matches; unavailable results are penalized.
This is metadata relevance, not audio similarity. Results appear incrementally
and can move as better matches arrive. At most three sources run concurrently,
with a 25-second deadline per source request; some providers time out sooner.
Changing the query, hiding Online or leaving search cancels outstanding work.

A slow or failed source does not remove other results. Its inline Retry or Verify
action reruns only that source. Verification browser time is excluded from the
request deadline. Pasted collections retain the source's order when opened.

Each result has a small source badge on its artwork, with the source name in its
tooltip/accessibility label. Spotify, SoundCloud, YouTube and Tidal use bundled
brand glyphs; Qobuz and Monochrome use letter marks. The badge identifies the
catalog result: Spotify audio still resolves through the chosen audio provider.
Playback and Send to folder retain the selected result's source identity.
Duplicates within one provider are removed; copies across providers, remixes and
different uploads remain separate so you can choose the version you want.

### Playback details and quality

Now Playing shows the audio provider's colored icon and name; Spotify catalog
matches show the provider actually supplying audio. Your server songs show a
library icon and **Navidrome**, rather than implying the file is on the phone.
Known codec/format and kbps appear alongside the source. Prepared local files are
probed without blocking playback; direct streams use provider-reported bitrate
when available. An **≈** marks a file-level estimate that can include artwork or
container overhead. Unknown bitrate stays absent, and bitrate is not a measure of
lossless compression quality or the original upload's quality.

If playback fails, tap **Playback details → Copy diagnostics** and include the
report when describing the failed song/action. It is also available under
**Queue → Player info → Playback details** after recovery. Capture it before
restarting: the last 80 events live only in memory. Reports contain fixed stage
labels, timing, provider versions, recognized failure reasons, and HTTP/native
codes; they omit song names/IDs, account data, addresses, paths, URLs and raw error
text. Nothing is automatically uploaded. Release builds include the app version.
An unclassified error needs further investigation; this report does not claim an
upstream service has been fixed or bypass verification.

Reports also include operation numbers and known method names, plus temporary
recording numbers assigned in memory. A `match` event links Spotify's catalog
recording to `matched_recording` on its audio provider. Compare these numbers to
tell whether direct and matched selections resolve the same recording; the
numbers have no meaning outside that app session. The bounded identity map may
assign a fresh number to an old entry after 512 distinct recordings.

Qobuz resolution failures include sanitized `provider_failures` entries with
candidate ordinals, quality codes, recognized service codes and retry modes.
Unknown codes are reported as `UNRECOGNIZED`, never copied as arbitrary text.
An exhausted provider chain stops automatic player retries; manual Play remains
available. Network interruptions can still recover automatically. Errors are
scoped to their recording, so a different queued song's preload cannot overwrite
the current error. Selecting Spotify can match a different edition on the chosen
audio provider; success there does not guarantee that every direct result works.

### SoundCloud

Install SoundCloud in Home > Music sources, then hold Online in Search and choose
SoundCloud. Search uploads, remixes, albums and playlists, or paste a public link.
Use the shared player and the same song/collection download controls to send
audio to your saved Remote folder. No new server or gateway verification is
required by this pinned extension, and it has no account configuration fields.

Native playback streams a full progressive M4A/MP3 when available. HLS-only
uploads are downloaded and remuxed privately before playback; long DJ sets may
take longer to start and remain subject to execution/transfer time limits. Opus
fallbacks use the existing temporary AAC playback conversion. The import path
keeps lossy AAC/MP3/Opus/Vorbis audio packets without re-encoding. Codec detection
uses the downloaded audio, not its filename: AAC in M4A is preserved, while ALAC
in M4A is lossless and converts to MP3 320. Bitrate is not increased artificially.

Preview-only, blocked and nonstreamable uploads are marked unavailable when the
provider exposes that status and rechecked at acquisition. A set with missing
records fails rather than silently importing a shortened or reordered playlist.
Repeated entries remain in playback and are imported once per upload. Provider
availability can change; the extension uses SoundCloud's web interfaces, not a
Hyperstream-hosted official API application.

Validation: live search, public-link identity, complete AAC HLS download, duration
and local MP3 320 conversion passed on Windows. Automated tests cover ordering,
missing records, playback resolution, unavailable uploads and import routing.
Verify iPhone playback/seek/lock-screen behavior and an actual Send to folder on
your device; the automated checks do not access personal remote destinations.

Songs download into a private temporary directory. Lossless audio converts with
LAME to stereo 44.1 kHz MP3 at 320 kbps. Supported lossy audio is remuxed with
stream copy, preserving codec, sample rate and channels. Every output undergoes
duration and audio validation before publication; MP3 conversions also verify
320 kbps. Title, artist, album, track/disc number and ISRC are written as tags.
Artwork is included where supported; failed artwork retries with audio only.
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

After a playback error, Play, automatic recovery or choosing another song releases
the native player and renews the local external-stream session before loading.
Retries preserve the queue, selected song, position, shuffle order, repeat,
volume and tempo. Pause or changing the queue still wins over pending recovery.
A native error releases an unfinished load immediately, so the serialized retry
can reach its reset even if the original native load never finishes.
The old listener's requests are canceled; late resolutions cannot evict new
streams or overwrite their status, and late prepared files are cleaned up.
Bad stream URLs are evicted, while normal native seek/preload cancellations
retain prepared audio. A pending verification for one service does not block
unrelated sources. Recovery remains bounded and cannot make an unavailable
recording or rejected provider session playable.

The supported packages are Spotify Web 1.10.6, Tidal Web 1.2.14,
Qobuz Web 1.2.27, YouTube Music 2.4.7 and SoundCloud 1.0.15. This is a reviewed subset of the Mornye JavaScript ecosystem;
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

YouTube searches merge YouTube Music's general and Videos categories. General
results alone can omit creator mashups and edits that lead the Videos category.
The adapter interleaves the two bounded result sets, removes duplicate upload IDs
and retains distinct uploads and albums; the shared search then ranks by relevance.
Creator names need not match the artists named in a mashup's title. Search still
uses YouTube Music's index rather than unrestricted YouTube video search.
Pasted videos keep their exact upload ID, uploader, title and available
thumbnail/duration. Native playback prefers M4A and forwards only the resolver's
public User-Agent, Origin and Referer headers. If a direct link remains blocked,
the package downloader tries its supported paths. Opus/WebM/Ogg playback copies
are converted to AAC for the native players, so fallback playback may take longer
to start. Imports keep the original lossy audio without another lossy encode,
using the acquired source file rather than the temporary playback copy. There is no
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
