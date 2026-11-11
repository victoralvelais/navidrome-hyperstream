# Recent Radio: sideload and device acceptance

This milestone adds counted listening and a playable Recent Radio preview. The
Home page now contains settings directly; navigation is Home, Library, Search.
Use the new matched IPA/Windows pair in the directory referenced by
`releases/latest.json`. Keep older releases available for comparison. The IPA
still needs signing through the existing sideload workflow; Windows needs the
whole extracted bundle, not only its EXE.

## Try the radio

1. Open Library > Playlists > Recent Radio, or choose Recent Radio from the plus
   menu. The first load reads the entire song catalog; progress shows the count.
2. With the initial 30-day window, compare several tracks against their added and
   last-played dates in Navidrome. A song qualifies if either date is recent.
   Its position uses the later date. Equal dates are ordered by track ID.
3. Change the day window and name, then tap Update preview. Reopen the radio and
   restart the app to check that its settings persist for this account.
4. Tap Play radio or a song. Pull to refresh while it plays: the current queue
   should retain its original order. New history is reflected when you refresh,
   reopen the radio, or return to the app, without rearranging an open preview
   on every reported listen.
5. Try another saved account. Its rule and preview should be separate. Return to
   Home's Servers page to switch back. Opening an unsupported/incomplete server
   response must show an error instead of publishing a partial result.

## Verify listening history on the actual server

1. Check Home > Playback > Report listening history. It starts enabled; existing
   server settings may also forward these listens to external scrobbling services.
2. Note a track's play count in Navidrome. Play a track longer than 30 seconds for
   half its duration or four minutes, whichever is shorter. For a three-minute
   track, listen for at least 90 seconds, then refresh Navidrome and Recent Radio.
   Expect one new play and a current last-played date for the signed-in user.
3. Pause for part of that interval, buffer on a poor connection, or seek near the
   end after a short listen. Those intervals/jumps should not earn listening time.
4. Repeat a qualifying listen with the iPhone locked/backgrounded. Check the lock
   screen controls and server result. This is an outstanding device acceptance
   check, not something the fixture tests establish.
5. Disable reporting and listen again: no new Hyperstream submission should occur.
   Re-enable it to start collecting fresh listening time. Switch accounts mid-song
   and verify that the old track does not count against the new account.

## Recovery and current boundaries

- Lose the network after a successful preview and refresh. The old preview remains
  labeled as the last successful result, with Retry. Failed pages are never
  accepted as a complete new preview.
- A server may accept a listen even if its response is lost. The app attempts each
  listen once and reports uncertainty under Playback; it does not automatically
  retry, avoiding duplicate counts. There is no offline history queue yet.
- Unobserved runtime gaps over five seconds are conservatively excluded. Long
  system suspension can undercount a listen; device testing will guide refinement.
- Radio settings live on this device. This release has one configurable Recent
  Radio preset, not a general rule editor or a generated Navidrome playlist.
  Managed saving/conflict handling and custom mixing are the next increments.
- No new provider, acquisition integration, companion service, or addon is included.

Automated coverage uses API fixtures and fake native audio to verify window
boundaries, date parsing, full pagination, stable ordering, account isolation,
pause/seek/buffer counting, uncertain submissions, persistence and responsive UI.
No usable saved desktop account was available for an authenticated live API check.
Installed-server compatibility and physical-device background behavior remain
explicit acceptance items for this release.
