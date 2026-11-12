# Recent Radio: sideload and device acceptance

Recent Radio stays a fixed built-in radio with immediate local listening updates
and a separate 30-minute catalog sync schedule. Its sync status now shows a progress
bar and the catalog total. Configurable Rules and Mix playlists are a separate
feature with their own [device checks](SMART_PLAYLISTS_TESTING.md).

Use the matched IPA/Windows pair referenced by `releases/latest.json`. The IPA
still needs the existing sideload signing workflow; Windows needs the complete
extracted bundle. Older releases remain available for comparison.

## Try local activity and sync

1. Open Library > Playlists > Recent Radio (also available from the plus menu).
   The first visit loads the full catalog. There is no name/window editor: the
   rule is added OR played within 30 days, newest activity first, ties by track ID.
2. Play an older song from Search, an album, or a playlist. For a three-minute
   song, listen for at least 90 seconds. Open Recent Radio without refreshing:
   it should now include the song near the top. The library sync time stays the
   same. Repeated listens reorder the existing song instead of duplicating it.
3. Tap Play radio. Let a song qualify while viewing the list: its row can move,
   but the current playing queue keeps its original order.
4. Pull down to refresh (F5 on the focused list on Windows). Newly added server
   music and listens from other clients should appear. The library sync time
   advances after a successful complete sync.
5. Leave the app active for 30 minutes after a sync, including on other app pages.
   The next scheduled sync should happen without reopening Recent Radio.
6. Background briefly and return before the interval: no extra sync. Return
   after more than 30 minutes: one overdue sync, without replaying missed intervals.
   The app does not promise scheduled syncs while suspended or closed.
7. Switch saved accounts: previews, local activity and timers must stay separate.
   Restarting the app clears the session cache; first open loads from the server.
   The old release's name/window preferences are untouched but no longer used.

## Verify sync progress and totals

1. Refresh Recent Radio. Expect a progress bar with a stable total such as
   `12,430 tracks`, not a growing fetched-song count or page/search offset.
2. Compare the total with the same account's accessible, non-missing songs in
   Navidrome. This is the full catalog, not the subset matching the 30-day radio.
3. The bar stays below 100% until paging and metadata validation finish. A complete
   successful sync shows the actual distinct track count and a full bar, including
   `0 tracks` for an empty library. The last-sync time advances only on success.
4. If the optional native count endpoint is unavailable, blocked or too slow,
   expect an indeterminate bar with “Syncing library” and no guessed number.
   Catalog syncing and sign-in still work. An actual total appears on completion.
5. If tracks are added during sync and fetched tracks exceed the original count,
   the stale total is withdrawn; paging continues to the end. The completed total
   reflects the pages actually accepted. A failed sync does not show completion.
6. Check a non-admin account with limited library access, reverse-proxy subpaths,
   and different saved servers. Counts and native sessions must stay account-scoped.
   Qualified listens still update immediately, without either a scan or count lookup.

## Verify listening history on the actual server

1. Home > Playback > Report listening history starts enabled. Tracks longer than
   30 seconds count after half their duration or four minutes, whichever is shorter.
   This existing qualification threshold also triggers local radio updates.
2. Compare Navidrome's play count and last-played timestamp before/after a qualified
   listen. Server-configured external scrobblers may also receive these submissions.
   The radio should update before acknowledgement, without refreshing it.
3. Pause, buffer, or seek near the end after a short listen. These actions should
   not earn listening credit. A playback instance should count only once.
4. Repeat with the iPhone locked and use lock-screen controls. Physical-device
   background counting and installed-server compatibility still need acceptance.
5. Disable reporting: local listen tracking and server submissions both stop.
   Re-enable it to start fresh. Switch accounts mid-song and verify isolation.

## Recovery and boundaries

- Lose the network after a successful sync. The current list and last-sync time
  remain visible with an error. Local qualified listens still update that list.
- A slow sync must preserve newer listens made while it was reading pages. A
  subsequent complete sync honors server deletions. Failed/partial scans never
  replace the catalog; failed scheduled attempts wait another 30 minutes or an
  explicit refresh before retrying.
- An uncertain scrobble response is not retried, avoiding duplicate server plays.
  It does not undo the local radio update. Local events are session-only: they
  are not a durable offline history queue or a promise of server acknowledgement.
- Unobserved runtime gaps over five seconds are conservatively excluded and can
  undercount during system suspension. Device testing will guide refinement.
- Rules and Mix smart playlists are implemented separately; see their
  [device checks](SMART_PLAYLISTS_TESTING.md). Managed Navidrome playlist saves,
  provider imports, and addons remain future work.

Automated tests cover local updates without catalog requests, pending/failed
submissions, sync races, timing/resume/coalescing, account disposal, date rules,
pagination, count lookup/fallback, progress completion, queue stability and
responsive UI. API fixtures and fake native audio
cannot replace testing on the actual Navidrome server and sideloaded iPhone.
