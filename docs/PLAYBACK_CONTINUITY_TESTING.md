# Playback continuity: device checks

First paired continuity release: **0.1.0+39**, November 13, 2026. Use the release recorded in
`releases/latest.json`. Next is user testing, then collaborative smart-playlist
planning, then alignment on addons, external streaming and Navidrome imports.
Those later features are not part of this change. The user declined the Discord
webhook alternative; leave that investigation aside.

Device feedback on build 39: the saved song/position appeared correctly, but
pressing Play restarted at the beginning of the queue. The follow-up explicitly
loads the live paused selection/position into the native player before playing.
This also preserves any song selection, seek, shuffle or speed changes made
after restoration. Startup still restores paused without fetching audio.

The user selected a full queue rather than a collapsed history section. It opens
at the current song, directly above Up Next. Scroll upward to earlier entries;
only pulling past the actual beginning starts the existing sheet-dismiss gesture.
Earlier entries follow the current shuffle traversal when enabled and preserve
duplicate queue occurrences. They are queue entries, not a listening-history log.

## Expected behavior

After successful login to a remembered account, Hyperstream restores its queue,
selected queue position, song position, shuffle traversal, repeat mode and speed.
It opens paused. Press Play to resume; returning from the background without
terminating the app continues using the existing player as before.

Each server URL/username has a separate saved queue. Switching servers saves the
old queue and restores the new server's queue paused. Session-only logins do not
load or save continuity data. Clear queue and Disconnect clear the current saved
queue. Sleep timers and previously earned listen credit are not restored.
Restoration alone does not submit a listen or update Recent Radio.

Positions save every five seconds while playing, on playback state changes,
after seeks/edits, and when the app becomes inactive. Abrupt termination may lose
roughly the last five seconds plus any unfinished storage write. A completed
song restored at or beyond its duration opens at its beginning, paused.

Only metadata and queue positions enter application support storage. Stream URLs
are recreated from the verified login; credentials, audio bytes and scrobble
requests are not saved here. Queue and position files use atomic replacement
and matching generations, so checkpoints do not rewrite thousands of tracks.
Unknown/unreadable queue data is preserved and produces a notice without blocking
normal playback.

## First test: resume a normal queue

1. Install the continuity release over the existing app, keeping its data. Pick
   an album or playlist and start a track partway through the list. Build 36 had
   no saved queue, so create one in the new build first.
2. Seek to approximately 45 seconds, pause, and note the current song and first
   two upcoming songs. Wait a second for storage to settle.
3. Close/terminate Hyperstream in your normal sideload environment, then reopen.
   If LiveContainer keeps the guest process alive, also close/reopen the container
   so this tests a real restart. On Windows, close and reopen the application.
4. Confirm the same song, position and upcoming songs return, with no automatic
   sound. Press Play and confirm it resumes near that position and Next advances
   to the expected song.
5. Repeat the restart, but change the paused position before Play. Confirm playback
   starts at that new position. Also try selecting another song before Play.
6. Open the queue: it should start at the current song with Up Next below it.
   Drag downward to reveal earlier songs, tap one to return to it, and check the
   list updates around that occurrence. The panel should stay open while browsing;
   pull beyond the first song to close it. Repeat once with shuffle enabled.

## Follow-up checks

- **Playing and locked:** play for ten seconds, lock the phone, advance a track
  using the lock-screen control, and listen briefly. Terminate/reopen. Confirm
  the later track returns paused with a recent position. Artwork and system
  controls should continue working.
- **Shuffle and edits:** shuffle an album, enable Repeat All and change speed.
  Note Up Next, then restart. Confirm the same upcoming traversal, repeat and
  speed. Separately, with shuffle off, move/remove an upcoming track and restart;
  the edited order should persist. Repeated occurrences of one song are retained.
- **Accounts:** save a queue on A, switch to B and create another, then return to
  A. Each should restore its own song/position paused. A rejected server switch
  must not replace the active account's saved queue.
- **Clear:** use Up Next > Clear queue, restart, and confirm the player stays
  empty. Do not disconnect merely to test relaunch; Disconnect deliberately
  removes the current saved queue and saved sign-in.
- **Connection recovery:** after restoration, temporarily make the server
  unreachable and try Play. If playback fails, reconnect and press Play again;
  it should retry the same queue/position. If a track was removed from Navidrome,
  select another queue row instead. Startup still requires successful server
  login; this is not offline playback.

Report the first failed step, iOS/LiveContainer or Windows, and expected versus
actual song/position. Complete the first test before the follow-up cases.

## Automated validation

Regressions cover paused restoration, exact shuffle traversal, duplicate entries,
edits, account isolation, verified-login gating, temporary sessions, clears and
selections racing a disk read, periodic/lifecycle checkpoints, storage failures,
unknown schema preservation and no phantom listens. A real Windows native audio
test recreates the player, verifies lazy paused restoration and resumes playback.
The release always checks saved-queue restoration/checkpointing in a real Windows
app. HTTP playback, native seeking and transitions additionally run when a real
audio output is enumerated; runners without one report that smoke test skipped.
Hosted validation confirmed zero Windows audio outputs. The independent saved
queue check exposed just_audio's deferred initial seek when preloading is off;
restoration now explicitly seeks the idle player before publishing/saving state.
The Windows backend also applies saved shuffle traversal at load time, maps
permutation indices directly, and reads 64-bit initial positions for long tracks.
A native C++ check exercises that production permutation helper across all small
permutations and rejects invalid orders.
Physical iOS and Windows playback acceptance still requires the steps above.

The follow-up regression uses the real pinned just_audio player and replaces only
its native method/event-channel boundary. It reproduced null initial index and
position on activation before the fix, then verified explicit load targets after
the fix, including paused edits, exact shuffle, repeat, speed and a newly set sleep
timer. Service tests cover Pause/Clear during activation. Queue widget tests cover
opening at the current entry, selecting an earlier row and pulling closed only at
the beginning, alongside the existing overlay/layout checks.

Build 39 validation: all 251 Flutter tests, formatting and analysis passed.
The compiled C++ queue traversal checks passed. The Windows host passed protected
account storage, output enumeration and saved-queue restoration/checkpointing;
the full audio smoke test reported skipped with zero audio outputs. Both platform
packages succeeded in [run 39](https://github.com/victoralvelais/navidrome-hyperstream/actions/runs/43404649005)
from `e68cb4b6`. The release helper verified manifests/checksums, both downloaded
archives passed CRC checks, and the IPA bundle reports `0.1.0+39`.
