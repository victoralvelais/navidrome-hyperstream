# Hyperstream Windows playback extension

Vendored from `just_audio_windows` 0.2.3 in the pub.dev cache. The upstream MIT
license is retained in `LICENSE`. The target uses C++20 for standard WinRT
coroutines; inline member declarations in `player.hpp` omit redundant class qualifiers
for standard conformance. Playback behavior is otherwise unchanged.

`windows/just_audio_windows_plugin.cpp` adds the `dev.hyperstream/audio_outputs`
method channel:

- `getOutputs`: lists Windows audio render devices plus System default, including
  the selected output. A disconnected selection falls back to default on refresh.
- `setOutput`: accepts a device ID (empty string for default), validates it against
  the available outputs, and sets `MediaPlayer.AudioDevice` on this app's players.
- Newly initialized players inherit the selection. The choice lasts for this app
  session and never changes the Windows system default.

Enumeration uses WinRT asynchronous APIs and resumes on the calling apartment.
Native error details are not returned to Dart. The hosted Windows integration test
checks enumeration, default selection, and rejection of an unavailable ID. Actual
speaker/headphone switching still needs device acceptance.

This local package exists because the upstream plugin does not expose output
selection. When upgrading, port this small channel and rerun the hosted Windows
build and integration test; do not replace the package silently with pub.dev.

Reference: [MediaPlayer.AudioDevice](https://learn.microsoft.com/en-us/uwp/api/windows.media.playback.mediaplayer.audiodevice).
