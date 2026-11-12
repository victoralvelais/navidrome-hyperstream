# Smart playlists: device checks

This milestone adds selectable **Rules** and **Mix** editor types. It requires
only the existing Navidrome account. Addons, server export and background updates
with the app closed are deferred. Automated tests use synthetic API responses;
real server metadata, large-library timing and device usability still need testing.

## A configurable Recent Radio

1. Open Library → Playlists → + → New smart playlist. Leave type as Rules.
2. Name it “My Recent Radio”. Include ANY: Date added within 30 days, Last played
   within 30 days. Order: Latest activity. Leave exclusions and limit empty.
3. Preview tracks. Compare its membership/order with built-in Recent Radio after
   the same sync. The latest valid added/played timestamp wins; track ID breaks ties.
4. Change either window, add an exclusion such as duration less than 45 seconds,
   or set a limit. Preview again, then Save. Reopen/Edit and verify the choices.
5. Try a nested group: Include ALL → Favorite Yes plus a group matching ANY of
   Play count less than 3 or Last played not within 90 days. The latter also
   includes known never-played songs. Choose Least played order and limit 100.

## A recent discovery mix

1. Create another smart playlist and select Mix. The example starts with:

   | Pool | Condition | Order | Share |
   | --- | --- | --- | --- |
   | Recently added | Added within 30 days | Newest added | 60% |
   | Recently played | Played within 30 days | Most recently played | 40% |

2. Set a limit of 100 and preview. With sufficient distinct candidates, expect
   about 60 new-pool and 40 played-pool selections, spread through the queue.
   A track matching both appears once, credited to the pool that selected it.
3. Edit/add pools, such as favorites not played within 90 days at 20%, and adjust
   the first two to 50%/30%. Shares must total 100%. A 0% pool is disabled.
4. Observe requested versus actual contributions. With “Fill from remaining
   pools” on, other pools supply missing candidates. Off stops at the first
   exhausted enabled pool; an initially empty enabled pool yields an empty mix.
5. Switch Rules → Mix and verify pool settings survive. Save, reopen, edit and
   verify both types' settings persist. Only the selected type determines results.

## Updates, playback and storage

- Play uses all selected tracks, even when only 50 appear in preview. Tap a sample
  row to start there. Listening updates the results without changing that queue.
- With listening reporting enabled, a qualified listen immediately changes local
  last-played/play-count matches. Favoriting a song updates favorite conditions
  after the server accepts the change. Neither should cause a catalog scan.
- Pull-to-refresh syncs; the shared 30-minute timer runs while the app is active.
  Open/close different smart playlists and Recent Radio: reuse the same catalog.
  Updates from other devices appear at the next complete sync.
- Failed sync retains the last complete catalog with local updates. Save failures
  leave the editor open; retry. Failed/unknown stored schemas are never overwritten.
- Restart and confirm definitions survive. Switch account/server and confirm its
  own definitions/catalog; switch back and verify the originals. Local activity
  overlays and the catalog itself are session-only.
- Use phone portrait, enlarged text, iPad and Windows. Check nested rule dialogs,
  pool editing/reordering, discard confirmation, preview, save, delete and Back.
- Recent Radio stays a separate hardcoded 30-day entry. Its requested progress
  bar plus trustworthy total is recorded separately; current fetched counts are
  not a valid total. Native count discovery remains pending.
