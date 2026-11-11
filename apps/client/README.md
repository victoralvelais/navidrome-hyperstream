# Hyperstream client

The first Flutter slice connects directly to Navidrome, browses recently added
albums, lists their tracks, and sends an album queue to a native audio player.
It includes play/pause, previous/next, seeking, connection errors, and disconnect.
Wide windows show albums and tracks side by side; narrow windows use one pane.
The library uses an artwork-first layout with a floating mini player and an
expanded Now Playing sheet. Light, dark, and system appearance are available.
The current visual pass draws on the user-supplied
[Kanade gallery](https://www.reddit.com/r/UI_Design/comments/1wrj8d5/how_can_i_improve_the_uiux_of_my_app_more/)
and Apple's [materials guidance](https://developer.apple.com/design/human-interface-guidelines/materials).
Glass controls and navigation are implemented in shared Flutter code; they are
Liquid Glass-inspired surfaces, not Apple's native Liquid Glass renderer.

Home, Library, and Search are the main destinations, in that order. Library has Artists,
Albums, Songs, Playlists, and Favorites entries; wide windows use a sidebar and
an adjacent detail pane. Home contains grouped settings directly, with Appearance,
Playback, Servers, and account controls. It uses the full content pane on wide
windows. Discover reads server history. Hyperstream reports qualified listens
to Navidrome, and [Recent Radio](../../docs/RECENT_RADIO_TESTING.md) provides a
playable, per-user radio with a fixed 30-day window and immediate local updates.

The Search tab finds artists, albums and songs across the entire Navidrome library using
[OpenSubsonic search3](https://opensubsonic.netlify.app/docs/endpoints/search3/).
Typing waits 350 ms before sending a request; pressing Search submits immediately.
Artists, albums and songs page independently, with All/Artists/Albums/Songs filters.
Artists open their server albums, album results use cover grids, and songs use compact rows.
Opening an album or switching tabs preserves
the query and results, including across narrow/wide layout changes. Tapping a song
replaces the player queue with the currently loaded song results, starting at that
song. Fetching another page does not change a queue that is already playing.
Artist and song categories use OpenSubsonic's explicit empty-query browse contract;
an empty search field sends no search request; Discover loads its own categories. Artist albums use
[getArtist](https://opensubsonic.netlify.app/docs/endpoints/getartist/).
External-provider search remains future work.

An empty Search tab opens **Discover**, with artwork browse cards for Recently
added, Most played (server history), Rediscover (random albums), and the server's
genres. These use [getAlbumList2](https://opensubsonic.netlify.app/docs/endpoints/getalbumlist2/)
and [getGenres](https://opensubsonic.netlify.app/docs/endpoints/getgenres/), not an
external charts feed. Genre/newest/frequent collections page independently;
random picks refresh as a new selection. Type a query to use normal search.

Pull down at the top of library lists to reload, including empty/short lists.
There are no refresh toolbar buttons. F5 reloads the focused browsing list on
Windows. Playlist creation is a small plus beside the Playlists heading.

**Home** uses grouped Appearance, Playback, and Servers pages.
Servers supports adding named connections, switching, and removing saved servers.
Credentials and the selected server live together in secure storage. Existing
single-account records are read automatically and migrate in place on the next
save. A switch authenticates before stopping the queue and replacing the library;
failed authentication keeps the current connection. Disconnect removes only the
current connection, leaving other saved servers available at sign-in. Temporary
sign-ins preserve unrelated saved connections but do not restore automatically.

This client is independent of the Python import prototype. Provider acquisition
and server imports are not connected to this UI yet.

## Playlists and favorites

**Library → Playlists → Recent Radio** (also available from the plus menu) reads
the complete song catalog on first open and includes songs added or played within
30 days. It sorts by the later timestamp and explains each match. A counted listen
updates the list locally before the server acknowledges the report, without any
catalog request. Further visits reuse the account's session cache. Pull-to-refresh
or F5 syncs it; a 30-minute timer also syncs while the app is active, even on another
page. Returning after an overdue interval runs one sync. Play radio uses the
displayed order, and later list updates leave that playing queue unchanged. Failed
syncs retain local updates and the last synced library with an error.

Recent Radio is a fixed built-in feature, separate from the future smart-playlist
editor and custom mixing. The earlier editable name/window preferences are left
untouched but no longer used. Neither the cache nor unconfirmed local activity is
persisted across app restarts; there is no managed Navidrome playlist yet.

**Home → Playback → Report listening history** is enabled by default. Tracks
longer than 30 seconds count after half their duration or four minutes of actual
listening, whichever is shorter. Pause, buffering and seeking earn no credit.
Only one submission is attempted per playback instance; uncertain responses are
not retried. Reporting is best effort, without an offline outbox. Long unobserved
runtime gaps are conservatively excluded. Navidrome may forward submissions to
its configured scrobbling services. Verify foreground and locked-device behavior
using the [test guide](../../docs/RECENT_RADIO_TESTING.md).

- **Library → Playlists** browses your Navidrome playlists and starts native playback
  in their saved order. Create and rename your own playlists; song menus let you
  add songs or remove entries from a playlist you own. **Add songs** on an owned
  playlist opens a song search picker and leaves the current playback queue alone.
  Shared playlists are playable.
- **Library → Favorites** shows favorite albums and songs, with a play-all action
  for songs. Use the heart on albums and Now Playing, or a song's menu, to change
  favorites. Updates are saved in Navidrome and appear only after it confirms them.
- Song menus are available in albums, search, favorites, playlists, and Now Playing.
  Adding to a new playlist creates it with the selected song in one request.
- Editing a saved playlist leaves the current playback queue alone. Removing an
  entry checks the latest song order first, including duplicate songs. The API has
  no atomic version check, so simultaneous edits in other clients can still race.
- Disconnect is under **Home → Disconnect from server**, in the Account group.
  It stops playback,
  removes the saved account and returns to sign-in; there is no logout button
  in the main toolbar. A failed removal is shown and can be retried.

These features use [getPlaylists](https://opensubsonic.netlify.app/docs/endpoints/getplaylists/),
[updatePlaylist](https://opensubsonic.netlify.app/docs/endpoints/updateplaylist/),
and [star](https://opensubsonic.netlify.app/docs/endpoints/star/) through the same
authenticated Navidrome client. Artist favorites, playlist reordering, and playlist
deletion are not exposed yet. Tests use a local API fixture; live server/device
acceptance for these new features remains open.

## Volume, mixing, and appearance

- The mini player always shows previous/restart, play/pause, and next.
  Previous restarts after three seconds; near the beginning it goes back one track.
  On the first track it restarts. Paused playback stays paused.
- Tap the speaker to expand a vertical volume capsule, or press and drag up/down
  directly. Outside tap or Escape closes it; arrow keys adjust by five percent.
  The speaker inside the expanded control mutes/restores the prior audible level.
  This changes Hyperstream's independent music volume. Narrow screens and larger
  text use two mini-player rows to keep transport controls accessible.
- Scrolling down collapses the mobile dock into one floating row with navigation,
  the mini player, and Search. Scroll up or expand navigation to restore the full
  dock and its volume button. Enlarged text keeps the full layout. Dock animation
  respects reduced motion; list content can scroll behind the glass surfaces.
- Tap the track title or artwork to open Now Playing, with a larger cover,
  artwork-colored backdrop, transport controls, and seek bar. Seeking commits
  when a drag ends. The queue button shows the actual current queue and lets you
  jump to a track. Volume expands separately, with space reserved beside transport.
- Open **Home** for light/dark/system appearance and audio
  preferences. Volume (including mute), its restore level, mixing, and appearance
  are saved locally with `shared_preferences`. Credentials use separate secure storage.
- **Home → Appearance → Glass effects** switches between translucent and solid controls.
  High contrast and iOS **Reduce Transparency** automatically use solid surfaces.
  The iOS setting is read through a small native bridge, updates while running,
  and is checked again on resume. An unavailable bridge defaults to solid surfaces.
  Artwork backdrops are static, with no looping animation. Device performance and
  real iOS accessibility behavior still need hands-on acceptance.
- On iPhone/iPad, **Mix with other audio** enables the native audio session's
  `mixWithOthers` option. It is off by default. This lets Hyperstream share audio
  with other apps where iOS permits; it cannot guarantee playback through calls.
  Normal interruption and headphone-removal handling remains enabled.
- Windows already mixes ordinary application audio. The app volume is independent
  of other apps, but Windows communication settings can still lower music during
  calls. Device/system volume remains the overall output limit on every platform.
- Now Playing groups audio output selection beside volume. iOS embeds Apple's
  [AVRoutePickerView](https://developer.apple.com/documentation/avkit/avroutepickerview)
  and uses the system route sheet. Windows lists audio render devices and changes
  Hyperstream's player output through the [local plugin extension](packages/just_audio_windows/README.md).
  This does not implement Chromecast, Spotify Connect, or remote Hyperstream
  session handoff. Device routing and AirPlay playback need hands-on acceptance.

See Apple's [mixing option](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/mixwithothers)
and [interruption behavior](https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions).
Verify mixing with your particular audio/call apps on the phone; Windows tests
cannot establish iOS audio-session behavior.

## Coming from TypeScript and npm

Flutter is the app framework and command-line tool; Dart is the language. Xcode
is Apple's native build toolchain and IDE. Most app changes happen in `lib/`
using your normal editor; the iOS build workflow runs Xcode on GitHub's Mac.

| Familiar concept | This project |
| --- | --- |
| `package.json` | [`pubspec.yaml`](pubspec.yaml): app metadata, version, Dart SDK constraint, dependencies, and assets. |
| `package-lock.json` | [`pubspec.lock`](pubspec.lock): resolved direct and transitive dependency versions. Commit it for this app. |
| `dependencies` / `devDependencies` | `dependencies` / `dev_dependencies` in `pubspec.yaml`. |
| npm registry | [pub.dev](https://pub.dev), the Dart/Flutter package registry. |
| ESLint configuration | [`analysis_options.yaml`](analysis_options.yaml), used by `flutter analyze`. |
| Native iOS build configuration | [`ios/Runner.xcodeproj/project.pbxproj`](ios/Runner.xcodeproj/project.pbxproj), shared schemes, and `.xcconfig` files. |
| iOS app metadata and permissions | [`ios/Runner/Info.plist`](ios/Runner/Info.plist). |

Run Flutter commands from `apps/client`, where the pubspec lives:

| Task | Command |
| --- | --- |
| Install/restore packages | `flutter pub get` |
| Restore the committed lockfile strictly in CI | `flutter pub get --enforce-lockfile` |
| Add a dependency | `flutter pub add PACKAGE_NAME` |
| Add a development dependency | `flutter pub add --dev PACKAGE_NAME` |
| Run with hot reload on Windows | `flutter run -d windows` |
| Static analysis | `flutter analyze` |
| Unit/widget tests | `flutter test` |

These short commands assume Flutter is on PATH. On this PC, use
`& D:/Tools/flutter/bin/flutter.bat` in place of `flutter`, as shown below.
Pubspec does not provide npm's `scripts` section; the Flutter CLI supplies the
common commands and our GitHub workflow records the iOS build steps.

There is no single Xcode equivalent to `package.json`. Swift packages use
`Package.swift`, but this Flutter app gets its native plugin dependencies from
the pubspec. Flutter generates the Swift Package Manager integration during
setup/build, with CocoaPods fallback where needed. The generated
`ios/Flutter/ephemeral/` directory is ignored; the Xcode project and workspace
are committed. No hand-written `Package.swift` or `Podfile` is needed for the
current setup. See the [pubspec reference](https://dart.dev/tools/pub/pubspec)
and [Flutter's native package integration](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-app-developers).

The tested Flutter version is **3.47.9**, which includes Dart **3.13.7**. The iOS
workflow pins Flutter and Xcode versions. Downloaded packages, SDKs, build outputs,
generated machine-specific files, and signing credentials are excluded from Git.

## Run on Windows

Install Visual Studio 2022 Build Tools with **Desktop development with C++**,
including **MSVC v143**, **C++ CMake tools for Windows**, a Windows SDK, and
**C++ ATL for latest v143 build tools (x86 & x64)**. The secure-storage plugin
requires ATL (`atlstr.h`); the local VS 2019 installation currently lacks it.
The GitHub `windows-2022` builder supplies this toolchain and runs the native
secure-storage check before packaging the release. After changing local compiler
versions, run `flutter clean` and `flutter pub get` before rebuilding so CMake
does not reuse the old toolchain cache.

This workspace uses Flutter **3.47.9 / Dart 3.13.7**, installed at
`D:\Tools\flutter`. Its directory has not been added to your system PATH.
From the repository root:

```powershell
cd apps/client
& D:/Tools/flutter/bin/flutter.bat pub get
& D:/Tools/flutter/bin/flutter.bat run -d windows --dart-define=NAVIDROME_URL=http://localhost:4664
```

Enter your Navidrome credentials in the app. The address above is the existing
Docker port on this PC; the field is editable. A reverse proxy subpath is allowed,
for example `https://music.example.com/navidrome`. Use the final address rather
than a URL that redirects. `NAVIDROME_URL` only prefills the server field; it
contains no credentials.

For a standalone local debug build:

```powershell
& D:/Tools/flutter/bin/flutter.bat build windows --debug --dart-define=NAVIDROME_URL=http://localhost:4664
.\build\windows\x64\runner\Debug\hyperstream_client.exe
```

Keep the executable with its adjacent DLLs and `data` directory. This is a local
debug build, not an installer or release package. Flutter's environment check
accepts the installed Visual Studio Build Tools 2019 and Windows 10 SDK.

## Where to make changes

| Change | File |
| --- | --- |
| App startup and session lifetime | `lib/main.dart` |
| Startup progress and slow-start message | `lib/features/startup/startup_screen.dart` |
| Colors, typography, component styles | `lib/app_theme.dart` |
| Saved appearance and audio preferences | `lib/services/app_preferences.dart` |
| Settings sheet | `lib/features/settings/settings_sheet.dart` |
| Sign-in form and validation | `lib/features/connect/connection_screen.dart` |
| Album grid, pagination, responsive layout | `lib/features/library/library_screen.dart` |
| Library search, debounce, result paging | `lib/features/search/library_search.dart` |
| Shared server-backed playlists and favorites | `lib/services/library_collections.dart` |
| Playlist browsing, editing, and song picker | `lib/features/playlists/` |
| Favorite album/song collection | `lib/features/favorites/favorites_screen.dart` |
| Song menus and favorite buttons | `lib/features/library/collection_actions.dart` |
| Track list and album selection | `lib/features/library/album_tracks.dart` |
| Artwork loading | `lib/features/library/cover_art.dart` |
| Mini player, Now Playing, and seeking | `lib/features/player/player_controls.dart` |
| Vertical music volume control; Settings slider and mute | `lib/features/player/volume_button.dart`, `volume_controls.dart` |
| Native queue and system playback commands | `lib/services/playback_service.dart` |
| Navidrome endpoints, authentication, response parsing | `lib/services/navidrome_client.dart` |
| Album and track fields | `lib/models/library.dart` |

Screens use ordinary widget state and explicit constructor dependencies. There
is no state-management framework, code generator, or shared-package hierarchy.
One playback service lives above the screens. Replacing a queue is serialized;
new selections supersede older requests, and pausing during a load prevents
autoplay. The native queue owns track transitions.

`just_audio` provides the common player API. `just_audio_windows` supplies the
WinRT backend. On iOS, `audio_service` connects playback to system controls.
`audio_session` is configured at startup on both platforms; doing it lazily on
the first play exposed a WinRT paused-state race in the native test. Windows system media controls
are not wired yet. The adapter has an injectable player for command/queue tests.

## Credentials and audio

**Keep me signed in** is on by default. After Navidrome verifies the sign-in,
the server address, username, and password are saved together using
[`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage):
iOS Keychain with device-only access after the first unlock following a reboot
(no iCloud synchronization), and Windows DPAPI-protected storage under the user's
application support directory. There is no plaintext preference/file fallback.
The password is needed to generate fresh OpenSubsonic authentication tokens.

Startup restores the account and checks the server. A server outage offers Retry
and Edit connection while retaining the saved account. A rejected sign-in keeps
the address and username but requires password re-entry. Errors reported by secure
storage offer Retry or Forget; the app does not request deletion on a read failure.
Saves and removals are read back to verify success. Disabling **Keep me signed in**
removes saved credentials for that same server/account, preserves other connections,
and disables automatic restoration for the temporary session.
**Home → Disconnect from server**, in the Account group, removes the active connection and
stops playback. Other saved servers remain available from the sign-in screen.

The pinned Windows storage plugin can discard an encrypted container it cannot
decrypt or parse. In that case, a later launch requires signing in again. Account
retention through network outages is handled by the app; damaged OS storage is
not recoverable by the session controller.

Windows account storage is independent of the versioned release folder. Keep the
Windows product/company identifiers and iOS bundle identifier/signing identity
stable across upgrades so the OS can find the same protected account. Sideloading
under a different identity may require signing in again. The iOS entitlements file
is applied to Debug, Profile, and Release; the final signed app must retain valid
Keychain access. Device acceptance: sign in, force-close/reopen, test a temporary
server outage, then disconnect and confirm the next launch asks for sign-in.

The native secure-storage integration test uses a separate synthetic account key:
`flutter test integration_test/account_storage_test.dart -d windows`.
It checks protected multi-server write/read with a new store instance and verified deletion,
as well as Windows output enumeration/default selection and missing-device rejection,
without using the saved Navidrome account. Unit/widget tests cover cold startup,
network/authentication failures, rejected writes, and disconnect persistence.

In the Dart constructor,
`this._password` is a private field formal whose public named argument is
`password` (supported by the pinned Dart SDK).

Requests use OpenSubsonic salted-token authentication. Tokens in audio URLs are
still credentials: do not share player/network traces containing query strings.
The app does not log these URLs, persist queues, or echo raw transport errors.
Artwork is fetched as bytes so widget errors do not print its authenticated URL.
API requests reject redirects; native audio redirect behavior is platform-owned.
Use HTTPS for remote access. This prototype does not bypass certificate checks.

Playback requests the stored file (`format=raw`), with no second lossy conversion
or explicit permanent device download. Player buffering and operating-system
caches may still use temporary storage. Codec support needs representative files
on each platform; a future transcoding fallback is separate from server imports.

## Checks

Client checks cover formatting, analysis, and unit/widget behavior.
Earlier native Windows playback checks used the actual WinRT decoder and HTTP
playback, including automatic transition to a second track. Hosted release builds
also run the native Windows secure-account storage check.

```powershell
& D:/Tools/flutter/bin/dart.bat format --output=none --set-exit-if-changed lib test integration_test test_driver
& D:/Tools/flutter/bin/flutter.bat analyze
& D:/Tools/flutter/bin/flutter.bat test
& D:/Tools/flutter/bin/flutter.bat test integration_test/playback_smoke_test.dart -d windows
& D:/Tools/flutter/bin/flutter.bat test integration_test/startup_smoke_test.dart -d windows
```

Unit/widget tests cover authentication, URL encoding, malformed responses,
sign-in retries, queue replacement, pause during loading, reset, and errors.
They also check volume/mute ordering and recovery, preference persistence,
mixing configuration and failures, and the library/player/settings flows at
393px, 320px with larger text, 1024px tablet, and 1280px desktop widths.
Glass checks cover preference persistence, high-contrast fallback, and simulated
iOS Reduce Transparency events and native-channel failure.
Selected-design checks cover previous/restart at the three-second boundary,
direct volume dragging, keyboard/mute/dismissal, artist navigation, search filters,
playlist song picking, and keeping transport clear of the expanded volume control.
Search checks cover query encoding, empty and malformed responses, stale requests,
clearing/debouncing, page retries, result playback, and preserving results across
album navigation and window resizing.
Startup tests cover rendering before initialization, stage reporting, slow startup,
retry, disposal after closing, and unavailable or stalled preference storage.
The native startup test uses the real preferences/audio plugins and reaches the
sign-in screen without connecting to Navidrome or changing saved settings.

To render local UI previews with generated sample artwork and a local font:

```powershell
& D:/Tools/flutter/bin/flutter.bat test test/library_screen_test.dart --update-goldens --dart-define=CAPTURE_PREVIEWS=true --dart-define=PREVIEW_FONT=C:/Windows/Fonts/segoeui.ttf
```

Images go to `build/previews/` (ignored by Git). They are optional visual-review
artifacts, not platform-dependent golden baselines in CI. Dark/light phone,
enlarged-text phone, tablet, and desktop previews were visually reviewed.

The native integration test opens a test window and runs a temporary loopback
HTTP server with generated silent WAV audio. It checks decoding, advancing
playback, volume/mute, pause, seek, automatic album transition, and reset. It never connects
to the real Navidrome library or any third-party service.

The integration build replaces the debug executable with a test harness. Run
the regular `flutter build windows --debug` command afterward to restore the app.
These checks do not establish real Navidrome compatibility, MP3/FLAC/AAC coverage,
gapless playback, interruption handling, or iPhone background reliability.

## iPhone/iPad next

The generated iOS project includes the audio background mode, a local-network
usage description, and a local-network ATS exception. It does not enable arbitrary
insecure network loads. Prefer an HTTPS server for initial device validation;
local HTTP behavior still needs an iPhone check. `localhost` on a phone refers to
the phone, so use a reachable server hostname or the PC's LAN address instead.

iOS compilation requires macOS/Xcode. The project now has a manually triggered
[GitHub Actions build and sideloading guide](../../docs/ios-github-actions.md):
the hosted Mac compiles an unsigned release, and AltStore Classic/AltServer can
sign it locally from Windows. No paid Apple Developer membership or Apple
credentials in CI are needed for this route. The
[hosted build](https://github.com/victoralvelais/navidrome-hyperstream/actions/runs/42930047757)
successfully compiled and packaged the IPA, and the downloaded archive and
checksum were verified. The user has since confirmed that the sideloaded iPhone
app works; the new volume/mixing controls still need their own device check.

From the repository root, `python tools/release.py build` now builds both iOS and
Windows in GitHub Actions and collects a matching versioned pair in `releases/`.
`python tools/release.py fetch --latest` downloads an existing successful pair.
The Windows package is a release build with its required DLLs and data; the iOS
IPA remains unsigned. See the guide for folder layout, versions, and authentication.
Startup checks include unit/widget tests and a native Windows startup test.
The optional iOS simulator check remains experimental after hosted setup/build
timeouts; it does not yet establish a successful simulator launch.

The user reports working library playback on both Windows and the sideloaded
iPhone build. Broader device acceptance remains open.

First manual acceptance checks: connect to the real server, play and seek MP3,
FLAC, and AAC tracks, change albums rapidly, disconnect while loading, lose and
restore network access, and resize the window. On iPhone also check screen lock,
Control Center, track transitions while locked, headphone removal, interruptions,
and background recovery. Check saved sign-in across app restarts and signed iOS
updates. Queue restoration, system artwork, offline mode, and Mornye integration
come later.
