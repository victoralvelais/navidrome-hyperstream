# Hyperstream native camera access

Based on just_audio 0.10.6. Upstream Dart and playback behavior are retained.

The Darwin plugin publishes its instance through Flutter's plugin registry and
exposes its sole AVQueuePlayer to the camera bridge. Indexed items retain their
source request in memory so recording export can download the original audio
using the same authentication. Camera snapshots use the native item timebase.

When upgrading, reapply the small changes in JustAudioPlugin.h/.m,
IndexedPlayerItem.h, and UriAudioSource.m. Preserve the upstream LICENSE.
Credentials and request URLs must never be included in camera reports or
persistent take manifests.
