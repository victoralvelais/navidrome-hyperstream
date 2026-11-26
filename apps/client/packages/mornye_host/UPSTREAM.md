# Mornye host adapter

Hyperstream embeds Mornye's Rust extension runtime at
[`45df9860661e9c4e731ef26a60c44b2b5d8cf125`](https://github.com/mornyeapp/Mornye/tree/45df9860661e9c4e731ef26a60c44b2b5d8cf125),
whose compatibility version is 5.3.1. This is independent of Hyperstream's app
version. Runtime feature and minimum-version checks remain enabled.

The five supported JavaScript packages are pinned in `assets/catalog.json` to
Mornye-Extension revision `e9d2499688f77d8cbc224c1c1a1fe2ccfdb94555`. Installation
checks both the archive SHA-256 and manifest identity. The source archives are
not modified. `rust/src/adapter.js` adds explicit streaming/download entry points
when loading these particular package versions. Updates require reviewing their
contracts and updating the pinned registry together with adapter tests.

SoundCloud 1.0.15 uses its public web client bootstrap and direct SoundCloud media;
it does not declare a signed gateway session or user configuration. The adapter
retains exact upload IDs, adds playback-availability metadata, hydrates abbreviated
playlist records in their original positions and fails incomplete collections.
Playback refreshes track authorization and resolves progressive M4A/MP3, or uses
the original downloader for full HLS preparation. That downloader rejects previews,
checks HLS duration/end markers, supports byte ranges and initialization segments,
and remuxes only local files through the existing FFmpeg command pump. Downloads
request `aac_160` and use the actual returned M4A/MP3/Opus file extension before
Hyperstream's separate MP3 320/SMB import. No provider session or stream URL is
committed or stored in the playback queue. Long HLS-only sets can take longer to
start because they require preparation; the existing operation limits still apply.

YouTube Music 2.4.7 accepts regular YouTube video IDs as well as music searches.
General searches combine its general and Videos categories because creator
uploads may be omitted from the general response. The adapter retains creator
metadata and exact upload IDs, deduplicates category overlap, bounds the merged
list, and preserves explicit category requests. The app supplies relevance ranking.
The adapter reads pasted-video metadata synchronously, preserves repeated playlist
entries across continuation pages, and rejects interrupted pagination. Native
playback prefers direct M4A with the resolver's public request headers. Opus or
blocked direct streams use the extension downloader and a temporary AAC playback
copy when needed. Imports use the original downloaded audio for MP3 conversion.
The YouTube package does not declare the signed-session verification used by
Tidal/Qobuz; its optional token settings remain in Configure.

The host uses Mornye's network permissions, QuickJS limits, encrypted storage,
signed sessions, file grants, cancellation and FFmpeg command registry. File
grants cover a single private staging directory, never an SMB share. Hyperstream
provides the FFmpegKit command pump, native player and final MP3/SMB delivery.
Provider manifests and their callback protocol stay unchanged. Hyperstream's
scoped authentication browser captures the pending callback scheme without
registering Mornye's scheme globally. Playback and acquisition preflight signed
sessions before invoking the JavaScript adapter. A pending callback state must
belong to the requesting provider. Manual paste accepts the gateway's bare
`grant=...` fallback only against that provider's unexpired native challenge;
an explicit callback state must match. Verification values are never logged.

The runtime's Cargo workspace patches concern Android and Windows UNC paths.
This adapter currently targets iOS/Windows and gives the runtime only local app
storage; it does not access UNC paths. SMB remains in Hyperstream's existing
client. All resolved Cargo dependencies are pinned in `rust/Cargo.lock`.

## Build and replace

Install Rust 1.99.0 (`rustup toolchain install 1.99.0 --profile minimal`). On macOS,
also run `rustup target add --toolchain 1.99.0 aarch64-apple-ios
aarch64-apple-ios-sim x86_64-apple-ios`. Flutter's native asset hook builds the dynamic library
with `cargo +1.99.0 build --release --locked --target <target>` and bundles it into
the Windows distribution or iOS app framework. Native tests use `cargo +1.99.0
test --locked` inside `rust/`. Windows requires the Visual Studio C++ toolchain;
Apple builds require Xcode's SDK and libclang.
The hook supplies target-specific SDK and Clang arguments for QuickJS binding
generation, following Mornye's iOS build script. This keeps the header parser on
the iPhone or simulator SDK instead of the build host's macOS SDK.

To replace the runtime, change its Cargo dependency and rebuild this package and
the open-source app. The release workflow documents the complete build process,
including unsigned iOS packaging. No account data is needed to build or test.
Mornye and its linked libraries retain their licenses; the Hyperstream adapter
source is Apache-2.0. The combined dynamic library includes LGPL-3.0-only Mornye
code. Full notices are bundled in the app's open-source licenses screen and in
`apps/client/assets/licenses/MORNYE-NOTICES.txt`.

Generate notices from the locked graph with `tools/generate_mornye_notices.py`.
Package versions, source references, build configuration and the lockfile are
public; device keys, verification grants, provider settings and resolved audio
URLs are not repository configuration.
