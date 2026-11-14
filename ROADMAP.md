# Navidrome Hyperstream: draft roadmap

November 13 direction update: see [the direct SMB test](docs/REMOTE_FOLDER_TEST.md).
App-side acquisition/conversion and optional phone or remote-folder storage supersede
mandatory-companion/server-only proposals below.

Status: UI/multiple-server release complete at 0.1.0+14; counted listening and
Recent Radio shipped at 0.1.0+15. Release 0.1.0+17 keeps Recent Radio fixed at 30 days,
updates it immediately from local listens, and syncs on refresh/every 30 minutes
while active. Saved Rules and Mix smart playlists are implemented,
with shared condition groups, exclusions, track preview and ordered playback.
Server imports remain an isolated prototype; addons remain later work.
Updated: November 13, 2026.

Latest pre-addon release: **0.1.0+46**, paired iOS/Windows packages verified from
`131fd79ac04df32d9c02d99e02bf3513d27100f1`. Custom ranking, metadata filters and
explicit generated Navidrome copies are implemented; all 307 Flutter tests pass.
The next collaboration is addon/streaming/import design. Do not begin addon
implementation under the authorization for this completed batch. Physical-device
and live-server acceptance remains open in the linked test guides.

Playback continuity is implemented for remembered accounts: queue/current track,
position, exact shuffle order, repeat and rate restore paused after verified
login. Account changes preserve separate queues; clear/disconnect remove the
current saved queue. See [continuity testing](docs/PLAYBACK_CONTINUITY_TESTING.md).
Build 39 device testing exposed native Play resetting the restored selection;
the follow-up loads the live paused target explicitly before activation. The queue
now opens at the current song with earlier entries above it and Up Next below;
pull-to-dismiss begins only past the first entry. Device acceptance remains open.
The connection-recovery follow-up enables Play after playback errors, retries
unavailable saved-server logins and interrupted playback with bounded backoff,
and cancels playback retries on Pause/Clear/account changes. Startup recovery
continues to restore paused. The next device check focuses on outage recovery.
The user is testing playback and authorized smart-playlist work in parallel.
Artist spacing and saved stable shuffle shipped in build 42. Custom ranking now
adds independent point-based ordering to Rules and each Mix pool. The user has
authorized autonomous work through richer metadata filters and explicit generated
Navidrome playlist publishing, with paired sideload releases at each milestone.
Stop before addon implementation and align the addon/streaming/Navidrome import
vision together before beginning that architecture.
Discord webhook integration was declined and is not a pending milestone.

Current milestone: [Recent Radio and optional provider design](docs/SMART_PLAYLISTS_AND_PROVIDERS.md).
Device acceptance: [Recent Radio test guide](docs/RECENT_RADIO_TESTING.md).
After reviewing Feishin-informed proposals, the user selected both a rule editor
and a pool mixer as selectable editor types. Both use the same rule model and
account catalog. Artist spacing and stable shuffle are implemented in the current
follow-up. Custom ranking, genre/year/rating filters and explicit generated server
publishing are implemented. The authorized pre-addon scope is complete in code;
device acceptance remains open. Next: collaborate on the addon/streaming/import
vision before implementation. Native Navidrome rule editing remains an optional
future extension, separate from the generated ordinary playlist copies.
See [smart-playlist device checks](docs/SMART_PLAYLISTS_TESTING.md).
Recent Radio's status follow-up is implemented: a progress bar plus the current
catalog total replaces the growing fetched/search-count message. A bounded native
Navidrome count query uses the same account and excludes missing tracks. If no
reliable count is available, progress stays indeterminate until sync completes.
The status hides when syncing stops. The UI follow-up unifies smart and ordinary
playlists in one searchable list, adds selectable icons, floating title/corner
controls, left-edge Back, compact tab highlights and artwork-derived glass tint.
The follow-up navigation correction puts grouped settings directly on Home,
with Library in the middle and Search on the right. Continue producing paired
iOS sideload and Windows releases for user testing as milestones are completed.
The next UI batch adds continuous Now Playing, clearer refractive glass and glass
overlays, a separated/pinned Up Next layout, queue editing, shuffle/repeat, rate,
sleep timers, track actions, server ratings/lyrics and local-file system artwork.
The violet/gold equalizer icon is shared by launch, Home and platform app icons.
Device validation still includes background sleep timing, LiveContainer artwork
and Impeller refraction. Rules/Mix configuration and the fixed Recent Radio
behavior are unchanged; addon/provider work remains deferred to the next phase.

## Product direction

An iPhone-first music app that plays a personal Navidrome library and can search,
stream, and import music through replaceable third-party providers. Navidrome is
the permanent library. A companion service performs provider downloads on the
server, independently of whether the phone app is open.

Confirmed decisions:

- Platform priority: iOS, then iPadOS, then Windows.
- Distribution: personal use and sideloading first; consider the App Store later.
- Third-party downloads go to the Navidrome server only.
- Navidrome currently runs in Docker on the user's Windows PC.
- The user primarily works in TypeScript and has no local Mac; GitHub Actions now builds iOS releases.
- Language familiarity is not a constraint: Swift/native development, Flutter,
  and later ports are acceptable. Reliability and understandable, manually
  editable code are the main implementation priorities.
- Mornye was referenced for its SpotiFLAC lineage and provider/download ecosystem.
  Follow that ecosystem for acquisition and provider selection.
- Library output: MP3 at 320 kbps. Discard the downloaded FLAC source after the
  converted file passes validation and is safely published to the library.
  Original files may remain temporarily for recovery from a failed import.
- Flutter/Dart is the selected shared client, with small native bridges where
  needed. Continue device validation within this architecture.
- GitHub Actions is selected for hosted macOS builds. Begin with manually
  triggered unsigned release IPAs and local signing through AltStore Classic/
  AltServer on Windows. Hosted compilation and packaging are verified; device
  installation and basic playback are confirmed by the user.
- Independent app volume, optional iOS audio mixing, and an Apple Music-inspired
  interface with saved light/dark/system appearance are part of the client.

Proposed MVP boundaries:

- Multiple securely saved Navidrome accounts, one active server at a time, and
  an optional plugin-based acquisition backend. Validate
  a representative metadata/download provider combination first, then expand the
  tested compatibility list without hardcoding the client to those services.
- Direct native audio playback from Navidrome through OpenSubsonic.
- Search and playback of external music where the selected provider supports it.
- Explicit "Add to library" action for permanent server imports.
- No device download feature in the initial MVP. Transient playback buffering is
  separate from permanent downloads. Optional offline copies of Navidrome music
  can be discussed later.

## Visual direction: Kanade reference

Reference: [Kanade gallery by u/KayJune001](https://www.reddit.com/r/UI_Design/comments/1wrj8d5/how_can_i_improve_the_uiux_of_my_app_more/),
supplied by the user on November 11. All 11 screenshots were downloaded and
visually reviewed. Local originals and their source manifest are in
`.tools/design-references/kanade-reddit-1wrj8d5/` (ignored by Git).

Apply these patterns to Hyperstream's existing Apple Music-inspired direction:

- **Now Playing:** large square artwork, soft artwork-colored background, clear
  title/artist hierarchy, generous transport spacing, and circular favorite/menu
  controls. Use an independent speaker control that expands into a vertical
  volume capsule, with direct press-and-drag adjustment separate from seeking.
- **Album and playlist pages:** prominent cover and title, one clear Play action,
  compact secondary controls, and readable track rows. Preserve existing favorites
  and playlist editing while refining their presentation.
- **Mini player and navigation:** a compact floating player with artwork,
  previous/restart, play/pause, next, volume, and subtle progress. Keep navigation labels and reserve enough
  content padding that neither floating surface obscures the last item.
- **Library:** stronger headings, spacious cover grids, and easy access to favorite
  songs and playlists. Search/Discover reads server history. Hyperstream now
  submits qualifying listens, and Recent Radio previews added/played songs.
  Home houses settings.
- **iPad and Windows:** adapt navigation to a sidebar and make use of the existing
  split layout; give playback and the queue space alongside browsing.
- **Appearance:** retain Hyperstream's rose accent, refine dark surfaces using
  these references, and carry the same hierarchy into light mode. Check contrast,
  large text, focus/keyboard operation, and reduced motion/transparency behavior.
  Add Apple-style glass to controls and navigation, with opaque accessibility
  fallbacks and a saved user switch. Use shared Flutter rendering across platforms.

The user selected A/C's navigation and search, B's immersive atmosphere and
vertical volume, and C's mini player with an always-visible previous button.
The [consolidated concept](design/concepts/2026-11-11/selected-direction-v1.png)
and [interaction specification](design/concepts/2026-11-11/selected-direction.json)
record that direction. The first implementation of this selection includes:

- Home/Library/Search navigation, with sidebar navigation on wide windows.
- Library categories, artist albums, grouped search with filters and cover grids.
- Immersive album, playlist and player backgrounds; unboxed player transport.
- A persistent previous/restart button: restart at three seconds or later, go
  back near the beginning, restart on the first track, and preserve paused state.
- A vertical volume capsule with direct dragging, keyboard adjustment and mute.
  The expanded player reserves space so volume doesn't cover Next or seeking.
- An actual queue view and an Add songs picker for owned playlists.

The implementation includes unit/widget coverage for phone/tablet/desktop,
dark/light, enlarged text, navigation, volume and playlist editing. Glass can be
disabled; high contrast and iOS Reduce Transparency use opaque surfaces. Expansion
animations respect reduced motion. Native iOS appearance/performance still need
device acceptance. Lyrics, network casting, queue reordering, shuffle/repeat and queue
restoration require separate functional work. Concept artwork/counts are examples;
the app renders Navidrome content and does not invent library totals.

The follow-up revision uses grouped settings directly on Home, multiple securely
saved Navidrome connections, and a Discover landing page inside Search. Discover
offers server genres, recent additions, most-played albums, and random selections.
List titles use heavier, tighter typography; pull-to-refresh replaces refresh
buttons, and playlist creation is a small header action. Mobile navigation
collapses while scrolling and preserves previous/play/next. Now Playing groups
volume with an iOS system route picker or Windows app-specific output selection.
Native routing and the revised glass layout still require physical-device acceptance.

## Proposed architecture

```mermaid
flowchart LR
    App["iPhone / iPad / Windows app"] -->|"Library, playlists, audio"| Navi["Navidrome / OpenSubsonic"]
    App -->|"External search, play, import jobs"| Companion["Hyperstream companion"]
    Companion -->|"Mornye-Python integration and configured extensions"| Provider["Third-party services"]
    Provider -->|"Audio and metadata"| Companion
    Companion -->|"Temporary stream when supported"| App
    Companion -->|"Validate, convert, tag, publish completed files"| Music["Navidrome music folder"]
    Music -->|"Library scan"| Navi
```

The app connects directly to Navidrome for normal library use. An unavailable
companion must not prevent existing library playback. Provider credentials and
download jobs belong on the companion. The client stores its own server account
in iOS Keychain or Windows DPAPI-protected storage and restores the connection
on launch. Temporary network failures keep the saved account; explicit disconnect
removes it. A session-only sign-in option is also available.

Deploy the companion alongside Navidrome in Docker on the Windows PC. Bind-mount
the intended host library folder into the import worker, and keep downloads and
conversion staging outside Navidrome's scanned folders. Docker Desktop supports
sharing host paths into its containers; verify actual paths and permissions during
setup. See [Docker bind mounts](https://docs.docker.com/engine/storage/bind-mounts/).

The supported OpenSubsonic endpoint
inventory includes playback and scanning, but no general file-upload endpoint;
we will implement imports through the filesystem rather than assume an upload
API exists. See [Navidrome API compatibility](https://www.navidrome.org/docs/developers/subsonic-api/).

External streaming and importing are separate capabilities. Playing a result
must not silently add it to the permanent library. The provider feasibility
check must establish whether seeking, URL renewal, and progressive playback work.
A provider that only supports completed downloads must expose that limitation.

## Mornye integration: use the acquisition ecosystem

The acquisition backend is the relevant reference. Reusing or forking the mobile
player is not a product requirement. The mobile project's extension registry
distinguishes metadata providers from audio download providers; a Spotify link
can identify a recording without Spotify being the source of its audio. Preserve
both the requested recording and the actual audio source in our import records.
See the [Mornye extension registry](https://github.com/mornyeapp/Mornye-Extension/blob/main/registry.json).

The preferred feasibility candidate is
[Mornye-Python](https://github.com/mornyeapp/Mornye-Python). It documents headless
Docker operation, Python integration, and configurable JavaScript/Python
extensions. It ships without a provider or default registry. This is a separate
project: validate compatibility with chosen ecosystem extensions rather than
assume that it shares the mobile app's implementation or supports every plugin.

Its documented `/api/v1` exposes link resolution, search, download jobs, history,
and installed extensions. Integrate against that contract where suitable. The
REST documentation does not establish a pre-import audio-stream endpoint and
deliberately omits server file paths from download results. A server-side SDK
integration or verified completion hook/artifact handoff must connect acquisition
to conversion and publication. Do not infer completion from a file appearing in
a download directory. See the
[REST API guide](https://github.com/mornyeapp/Mornye-Python/blob/main/docs/guide/rest-api.md).

The [automation guide](https://github.com/mornyeapp/Mornye-Python/blob/main/docs/guide/automation.md)
documents typed post-download hooks carrying a result and file path, plus
Navidrome rescan support. Test these as the preferred handoff mechanism. Hook
errors are documented as logged and skipped, so upstream download success must
not mark our import complete when conversion or publication fails. Persist and
reconcile our import state independently.

Pin a tested backend version and extension versions. Keep the app-facing API
independent of provider internals. Check existing conversion and job capabilities
before adding our own; Hyperstream should supply only the missing orchestration
and Navidrome integration. The initial proof must exercise process restart and
repeated completion events, regardless of upstream persistence claims.

## Acquisition and conversion pipeline

Proposed order: resolve a link/search result, match the recording, acquire source
audio, validate, convert using the user's profile, preserve tags/artwork, publish
the final file, then reconcile with Navidrome.

- Prefer a lossless source when available. Convert to MP3 at 320 kbps for the
  library; retain source files only until validation and publication succeed.
- The [Python API reference](https://github.com/mornyeapp/Mornye-Python/blob/main/docs/guide/api-reference.md)
  documents conversion settings for several lossless formats and MP3, bitrate,
  and original retention. Evaluate `transcode_to="mp3"` and
  `transcode_bitrate="320k"`. Use temporary source retention in staging until our
  validation and publication complete, then remove the source. This is an import
  recovery measure, not permanent FLAC archival. Verify upstream conversion and
  hook ordering before relying on its cleanup behavior.
- Record the actual source format and output format. Do not label a converted
  lossy source as lossless or silently substitute a different recording.
- Keep an immutable conversion-profile snapshot per job, so a settings change
  does not unexpectedly change an in-progress import or retry.
- Validate output duration, decodability, tags, artwork, and track/disc ordering
  before publication. Treat conversion failures as recoverable import failures.
- Discard FLAC after successful validation and publication. If either fails,
  retain the staged source for retry; retry cleanup separately if publication
  succeeds but source removal fails. Never delete existing library tracks as
  part of source cleanup.
- Prototype against a disposable library, then configure the real Windows host
  paths. Nothing should alter existing library files as part of the prototype.

## Client framework decision

Choose for maintainability across the requested platforms, rather than language
familiarity alone. The recommendation is provisional until playback validation:

| Candidate | Main advantage for this project | Maintenance tradeoff |
| --- | --- | --- |
| Flutter/Dart | Share UI and application logic across iPhone, iPad, and Windows with one framework. | Native audio and system controls still depend on platform implementations; learn Dart and Flutter layout/state conventions. |
| Swift/SwiftUI | Direct access to Apple frameworks and native Apple interface behavior. | Windows needs its own UI/application implementation; iOS development needs a practical macOS workflow. |
| React Native/TypeScript | Existing language familiarity and shared React Native components. | Windows has a separate native host and dependency support matrix; mobile modules cannot be assumed portable. |

Flutter is the leading candidate for maintaining one client across all three
targets. SwiftUI is the preferred alternative if optimizing Apple integration is
worth maintaining a separate Windows client later. React Native remains viable,
but TypeScript familiarity alone is not a reason to select it.

Flutter shares rendered widgets and Dart application code across platforms and
can call native implementations when necessary. It does not automatically use
the system's SwiftUI controls. See the
[Flutter architecture](https://docs.flutter.dev/resources/architectural-overview)
and [native integration](https://docs.flutter.dev/platform-integration/platform-channels).
SwiftUI supplies Apple's declarative UI framework across Apple platforms; a
Windows client would be a separate implementation. See
[SwiftUI](https://developer.apple.com/swiftui/).

For a Flutter playback spike, evaluate `just_audio` with `audio_service` on iOS.
Their documentation covers audio queues, background playback, and system controls.
Windows playback needs an additional implementation, and `audio_service` does
not document built-in Windows support. Validate both playback and Windows media
controls before selecting the final dependencies. See
[just_audio](https://pub.dev/packages/just_audio) and
[audio_service](https://pub.dev/packages/audio_service).

Playback must outlive screen/widget lifetime. Keep one application-level playback
service with a small interface for queue commands, play/pause, seeking, and state
events. The selected engine must prove track transitions while backgrounded,
interruption recovery, and system controls on a real phone. Gapless playback is
a separate acceptance check, not an assumption based on a package feature list.

Keep the client straightforward to edit manually:

- Organize code by feature: library, search, player, imports, and settings.
- Keep each screen's presentation and state logic close together, in small files.
- Use plain models and explicit constructor dependencies with a consistent state
  convention. Avoid adding packages or generated layers without a concrete need.
- Isolate Navidrome HTTP calls, companion HTTP calls, and native playback so a
  change to one integration does not spread through every screen.
- Extract shared code when multiple features actually need it. Start with one
  client app rather than a large collection of workspace packages.
- Document where to change common behavior, such as album layout, queue policy,
  server settings, and the import conversion profile.

Python remains behind the companion's documented HTTP/OpenAPI contract, regardless
of client language. Navidrome is directly accessible through the client's
OpenSubsonic service, independently of acquisition. The existing Python prototype
does not commit the client to any framework.

The user has no Mac. GitHub Actions is the selected macOS build environment; the
initial workflow creates an unsigned release IPA for local signing and sideloading
from Windows. This supports phone testing without a local Mac, while interactive
native debugging remains less convenient. Hosted compilation and IPA packaging
are verified. See the [build guide](docs/ios-github-actions.md) and
[Flutter iOS setup](https://docs.flutter.dev/platform-integration/ios/setup).

## Milestones and completion criteria

| Milestone | Scope | Complete when |
| --- | --- | --- |
| 0. Feasibility and product decisions | Validate Mornye-Python in Docker, a metadata/download extension combination, MP3 320 kbps conversion and source cleanup, client framework, iOS build access, and server import destination. | A real Navidrome track plays while the phone is locked; one external track resolves, downloads, converts to MP3 at 320 kbps, and appears in a disposable Navidrome library with its staged FLAC removed after validation/publication; pre-import streaming and completion handoff behavior are documented. |
| 1. iPhone library player | Sign-in, artists/albums/tracks, search, artwork, queue, seek, shuffle/repeat, playlists, favorites, lock-screen controls, and queue restoration. | The app supports a normal listening session and recovers sensibly from network loss, interruptions, and relaunch. Test FLAC, MP3, and AAC files and any chosen transcoding fallback. |
| 2. Server acquisition | Authenticated companion, configured provider plugins, external search, supported external streaming, import jobs, conversion profiles, metadata, collision handling, and Navidrome reconciliation. | An import requested from the phone finishes after the app closes, appears in the chosen library format, becomes playable through Navidrome, and survives a server worker restart without publishing partial files or creating duplicate imports. |
| 3. Personal iPhone release | Playback reliability, useful failures, accessibility, storage limits, source/quality labels, sideload build instructions, and companion deployment instructions. | A repeatable signed build runs on the user's phone and handles representative home and mobile-network listening sessions. |
| 4. iPad experience | Sidebar navigation, simultaneous library/player/queue views, resizing, keyboard shortcuts, and pointer behavior. | The same library and provider workflows work in tablet layouts and narrow multitasking windows. |
| 5. Windows release | Desktop layout, native audio integration, media keys/system transport controls, keyboard use, packaging, and installation. | A packaged Windows build connects to the same services and completes playback and import workflows. |
| 6. App Store assessment | Review enabled providers, distribution rights, privacy disclosures, dependencies, platform requirements, and release configuration. | The intended feature set has a defensible submission path and the release is ready for review; approval is not assumed. |

Milestones describe delivery order, not calendar estimates. Estimate the work
after milestone 0 establishes the difficult integrations.

## First usable experience

Keep Home, Library, and Search, with a persistent mini-player and a full Now
Playing view. Home contains settings. Future import controls and job progress
appear when a companion is connected. Search identifies whether a result is already in
Navidrome or comes from an external service. External results expose Play when
supported and Add to library for a permanent import. Imports show progress and
specific recoverable errors.

An import progresses through queued, resolving, downloading, converting,
validating/tagging, publishing, waiting for Navidrome, and ready states. Failed and canceled are
separate states. A successful transfer is not "ready" until the corresponding
Navidrome track is discoverable.

Implementation requirements:

- Persist jobs and idempotency keys so retries and reconnects do not repeat imports.
- Stage downloads outside the scanned library. Publish validated files using a
  non-overwriting finalization step; account for cross-filesystem transfers.
- Check provider IDs, recording identifiers, duration, and release information
  when matching music. Do not silently replace a track with a different version.
- Use an incremental scan or the configured scanner behavior, then reconcile
  imported files with Navidrome IDs. Keep scan credentials on the server when
  needed, and avoid a full-library scan for every individual track.
- Keep provider tokens out of client-visible URLs and logs. Restrict provider
  network/file access and authenticate companion requests.
- Distinguish retryable network failures from missing tracks, authentication
  problems, unsupported capabilities, and unavailable quality levels.

## Deferred features

Additional providers, recommendation engines, lyrics enhancements, equalizers,
crossfade, CarPlay, widgets, multi-user administration, and offline device downloads
come after the core listening and server-import workflows. Evaluate gapless album
playback early if it is a personal must-have; do not assume a chosen player plugin
provides it reliably.

The server design avoids needing downloaded provider code inside the iOS app,
but it does not by itself establish App Store eligibility. Apple's current rules
address downloaded code and third-party media access/downloads; evaluate the
actual providers and release features at milestone 6. See
[App Review Guidelines, 2.5.2 and 5.2.2–5.2.3](https://developer.apple.com/app-store/review/guidelines/).

## Open decisions

- Which Mornye ecosystem extensions are compatible with the selected Python
  backend version? Establish this through the initial integration proof.
- What are the existing Docker deployment and host music paths, and can the
  companion write to a dedicated import destination?
- Does the phone handle longer listening sessions, interruptions, and mixed audio
  reliably? Basic sideloaded playback is confirmed; paid signing/TestFlight is deferred.
- Which remaining native playback/interruption cases need fixes in the shared
  Flutter client and its platform bridges?
- Which listening features are release requirements: gapless, AirPlay, CarPlay,
  lossless playback, or others?

## Current implementation evidence

The Python import prototype and documented Mornye hook adapter exist. Ten Windows
tests pass using actual generated FLAC audio and FFmpeg conversion; they cover
MP3 320 kbps output, metadata/artwork checks, collision protection, duplicate
events, restart recovery, and delayed source cleanup. See [README.md](README.md).

The first Flutter client slice exists in `apps/client`, with Navidrome sign-in,
paginated albums, server-wide album/song search, artwork, tracks, native queue/playback
controls, independent volume/mute, saved appearance, and iOS audio-mixing preferences. Unit/widget tests
and a native Windows integration test cover this slice. The native test
uses generated silent audio and a temporary loopback server to verify playback,
volume/mute, pause, seek, automatic track transition, and reset. The user reports
working Windows and sideloaded iPhone playback; broader acceptance checks remain.
See the [client guide](apps/client/README.md) for setup and remaining checks.

Playlists now support browsing, native queue playback, creation, renaming, and
adding/removing songs from owned playlists. Favorites sync albums and songs with
Navidrome and are accessible from the library, search, and player. Disconnect is
available in Settings. API-fixture and widget tests cover these features; live
Navidrome/device acceptance remains open.

Docker verification was prepared but execution was not approved, so container
behavior remains unverified. No live provider integration, Navidrome indexing,
comprehensive real-library acceptance, or new iOS mixing validation is complete.
Milestone 0 is open. The GitHub Actions iOS workflow and macOS packaging script
passed [hosted run 2](https://github.com/victoralvelais/navidrome-hyperstream/actions/runs/42930047757),
including Dart checks, Xcode compilation, IPA packaging, and artifact upload.
The downloaded archive, checksum, device-platform metadata, and app executable
permissions were verified. The user subsequently confirmed working iPhone playback.

## Flutter and a Docker-hosted web client

Keep Flutter as the primary client for iOS, iPadOS, and Windows. It already talks
directly to Navidrome and exposes native audio-session and player controls. A
TypeScript PWA remains a possible secondary client; it would need its own browser
audio/background acceptance checks, and would not remove the iOS signing step
for the existing native app.

Docker is the server deployment choice, independent of the client framework.
The companion will run acquisition providers, convert to MP3 320, validate and
publish files, discard the staged FLAC after success, and request/reconcile a
Navidrome scan. Navidrome's documented Subsonic API has playback and scanning,
but no general-purpose library upload endpoint. Both Flutter and a PWA would call
the same authenticated companion API for imports. Normal library listening should
continue directly through Navidrome even if that companion is unavailable.

Secure saved server sign-in and the selected glass/navigation design are implemented.
Next client slice: device acceptance, listening history and playback-mode refinements.
The next server slice remains an authenticated
companion job API and a provider-to-library import proof.
