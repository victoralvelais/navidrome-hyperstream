# Playback continuity: device checks

Implemented November 13, 2026. Use the paired iOS/Windows release recorded in
`releases/latest.json`. Next is user testing, then collaborative smart-playlist
planning, then alignment on addons, external streaming and Navidrome imports.
Those later features are not part of this change. The user declined the Discord
webhook alternative; leave that investigation aside.

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
That check is a required release step; physical iOS acceptance requires the
steps above.
