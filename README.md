# Navidrome Hyperstream

An iPhone-first music app project with iPad and Windows planned next. Navidrome
serves the permanent library. A server companion will use the Mornye acquisition
ecosystem, convert imports to MP3 at 320 kbps, and discard staged FLAC sources
after successful validation and publication.

See [ROADMAP.md](ROADMAP.md) for the product plan. The first client prototype uses
Flutter to share application code across iPhone, iPad, and Windows. Reliability
and code that is easy to edit manually take priority over language familiarity.
The user has confirmed working playback on Windows and a sideloaded iPhone build.

## What exists

The [Flutter client](apps/client/README.md) provides Navidrome sign-in, paginated
album browsing, server-wide album/song search, playlists, favorite albums/songs,
artwork, track lists, and a native queue with play/pause, previous/next, and seeking.
Own playlists support creation, renaming, and adding/removing songs. Disconnect is
in Settings. It has iOS and Windows hosts, layouts for narrow and wide windows,
and in-memory credentials. It now includes independent app volume,
mute with level restoration, saved light/dark/system appearance, an expanded Now
Playing view, and an optional iOS audio-mixing setting. Unit/widget tests cover
audio commands, preferences, and responsive UI; a native Windows test checks
HTTP playback, volume/mute, pause, seeking, track transition, and reset with
generated audio. Comprehensive codec/interruption and new iOS mixing checks remain.

The server prototype provides a SQLite import journal, a CLI, a Mornye completion
hook adapter, and a real FFmpeg conversion pipeline. It validates output codec,
bitrate, duration, core tags, embedded artwork count, and decodability, publishes
without replacing an existing destination, then removes the staged source.

Ten tests pass on Windows with Python 3.13 and FFmpeg, including actual audio
conversion, duplicate events, publication interruption, conflicting destinations,
changed sources, and failed cleanup. Tests generate their own audio and artwork.
The hook is tested with objects matching the documented interface; no live Mornye
provider or Navidrome connection has been exercised. Docker verification was
prepared but not run because execution approval was declined.

## Run the client

The Flutter manifest is [`apps/client/pubspec.yaml`](apps/client/pubspec.yaml),
with resolved dependencies in [`pubspec.lock`](apps/client/pubspec.lock). Both
are committed alongside the native iOS and Windows projects. The
[TypeScript/npm comparison](apps/client/README.md#coming-from-typescript-and-npm)
explains the files and everyday commands.

Flutter is installed at `D:\Tools\flutter` on this PC. From the repository root:

```powershell
cd apps/client
& D:/Tools/flutter/bin/flutter.bat run -d windows --dart-define=NAVIDROME_URL=http://localhost:4664
```

Enter credentials in the app. See the [client guide](apps/client/README.md) for
build/test commands, the file map, and iOS requirements. The client does not yet
connect to the acquisition worker.

## Build for iPhone and iPad

The manual [GitHub Actions workflow](.github/workflows/ios-sideload.yml) builds an
unsigned iOS release on a standard macOS runner and packages it for local signing
with AltStore Classic/AltServer. It requires no Apple credentials in GitHub.
See the [setup and sideloading guide](docs/ios-github-actions.md).

The [verified hosted build](https://github.com/victoralvelais/navidrome-hyperstream/actions/runs/42930047757)
compiled, packaged, and uploaded an unsigned iOS release. The downloaded archive
and checksum were verified. The user subsequently confirmed working iPhone playback.
Public repositories have free standard runners; private repositories use their
account's included allowance and billing rules.

## Run the isolated prototype

Requirements: Python 3.11+, FFmpeg with libmp3lame, and ffprobe on PATH. No Python
packages need to be installed for this prototype.

```powershell
python -m unittest discover -v
python -m hyperstream --root .sandbox status
```

The second command creates the dedicated `inbox`, `state`, and `library`
directories under `.sandbox`. Place a disposable copy of a completed, tagged
FLAC in `.sandbox/inbox`, then use:

```powershell
python -m hyperstream --root .sandbox enqueue .sandbox/inbox/example.flac --key example:recording-1
python -m hyperstream --root .sandbox process
python -m hyperstream --root .sandbox status
python -m hyperstream --root .sandbox process --retry-failed
```

Use a stable acquisition key: sending the same event again returns the existing
job. A successful import removes the staged FLAC copy. `published` means the
validated MP3 exists in this prototype's library; it does not mean Navidrome has
scanned or indexed it.

The isolated container check is:

```powershell
docker compose -f compose.prototype.yml run --build --rm verify
```

This builds an image with FFmpeg and runs the same tests. The test container has
no network and mounts no host music folders. The image build needs network access
to download the base image and packages. The Dockerfile is a feasibility image,
not a pinned production deployment.

## Mornye handoff

The candidate entry point is `hyperstream.mornye_hook:on_track`, using the
[documented completion-hook interface](https://github.com/mornyeapp/Mornye-Python/blob/main/docs/guide/automation.md).
Set `HYPERSTREAM_ROOT` to a dedicated directory and configure Mornye to download
unconverted FLAC into its `inbox` subdirectory. The hook queues an import; the
separate `process` command performs conversion and publication. Runtime
compatibility and whether this hook can be wired through the chosen web deployment
still need verification. No provider registries are installed by this repository.

## Prototype limits

- A CLI, import worker, and initial Flutter client exist. The companion HTTP API
  and client acquisition/import screens do not yet exist.
- Tests cover process interruption/retry behavior, not power-loss durability.
- Atomic publication uses hard links, so `state` and `library` must be on the
  same filesystem with hard-link support. Unsupported mounts fail while retaining
  the source. Windows Docker bind-mount behavior remains unverified.
- The root is owned by this prototype. Do not point it at an existing library.
  Acquisition inputs must be complete and stable; concurrent external edits are
  unsupported. Metadata-derived folders are sanitized for Windows filenames.
- Event-key deduplication is not recording-level deduplication across providers.
- A new FLAC downloaded for an already published event is not deleted by replaying
  the event. Preventing redundant upstream acquisition needs later coordination.
- Only completed FLAC inputs are supported. Conversion retains MP3-compatible
  sample rates; other rates are mapped to 44.1 or 48 kHz. Unsupported metadata or
  artwork conversions fail validation and retain the source.
- No Navidrome scanning/reconciliation, pre-import external streaming, or background
  companion-service installation has been completed. Broader iOS acceptance remains open.
