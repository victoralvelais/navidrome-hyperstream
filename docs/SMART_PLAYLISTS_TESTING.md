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
- Recent Radio stays a separate hardcoded 30-day entry. Its sync status now shows
  a progress bar plus the catalog total. Smart-playlist syncs use the same status.
  When the optional count lookup fails, the bar stays indeterminate. The bar and
  total disappear when syncing stops. No fetched-count sentence appears.

## Unified playlist UI and navigation (November 12)

- Open Playlists: saved smart playlists appear first in the same list as server
  playlists and Recent Radio. The plus menu has exactly New playlist and New
  smart playlist. Search filters all entries by name; clear restores them.
- Tap a playlist's icon, choose another, then restart. Verify persistence and
  server/account isolation. Default restores Sparkles for a smart playlist,
  Radio for Recent Radio, or the server cover for an ordinary playlist. These
  choices do not modify server artwork or the saved Rules/Mix definitions.
- Open a saved smart playlist directly. Its corner menu offers Edit configuration,
  Choose icon and Delete. Ordinary owned playlists retain Add songs and Rename
  in their corner menu. Shared playlists remain read-only on the server.
- Scroll Playlists: the large title moves into the glass top bar. At the top,
  Back and plus occupy separate glass circles. Check enlarged text and rotation.
- Swipe right starting at the left edge: return one menu. Interior/vertical drags
  must not go back. In a dirty smart editor, the existing discard prompt appears.
- Check the full floating dock: each selected capsule encloses its icon and label.
  Scroll down/up to check the existing collapsed player and previous/next controls.
- While one album plays, open a differently colored album or playlist. The selected
  cover should tint the page and floating controls without changing the queue.
  Verify light/dark mode, disabled glass and increased contrast.

## Player, glass and branding follow-up (November 12)

- Open Now Playing: no fixed title, chevron header or blank bottom band. Scroll
  with large text; dismiss by downward swipe, left-edge swipe or desktop Escape.
- Open Up Next with a populated queue. The current track is separate. Scroll
  the list under its pinned glass controls; reorder upcoming songs with shuffle
  off, remove one, and verify actual next playback matches the displayed order.
  Toggle shuffle and all repeat modes; changing them must not stop the song.
- Check original-file container/bitrate, playback rate, player info, lyrics,
  adding the queue (including duplicates) to a playlist, and Clear queue.
- Set a short sleep duration, background/lock the phone and verify it pauses.
  Check end-of-current-track with repeat off/one/all, manual seeking, cancel,
  queue replacement and disconnect. A native transition may select the next song
  before pausing; no sample-exact stop is claimed.
- Check Instant Mix against this server's similarity provider. Verify Show album,
  Show artist, favorite, rating (including removing it), Add to playlist and Share.
  There is no Delete cache action. Share contains song details only.
- Check Lock Screen and Control Center artwork on first play, next song, rapid
  queue replacement and account switching. Compare LiveContainer with a directly
  signed install if any problem remains; the previous missing-art-URI bug is fixed.
- Inspect refraction on iOS and clearer translucent glass on Windows. Toggle
  Reduce Transparency while a sheet is open and check the opaque fallback.
- Verify the violet gradient/golden sparkle app icon after installing the new
  IPA/Windows package. Home and launch/sign-in screens use the same mark and name.


## Device feedback follow-up: cache, lens edges and collection controls

- Sign-in/startup/Home: the violet mark remains square and centered. Default
  controls use violet and gold; artwork-derived page colors still apply.
- Albums, ordinary playlists, Rules/Mix results and Recent Radio: a circular
  Shuffle sits left of a centered Play pill. Albums retain Favorite on the right.
  Play restores the displayed order even after a shuffled session; Shuffle picks
  a random starting song and the native player shuffles the rest. Duplicates in
  an ordinary playlist remain distinct positions.
- Sync once, close/reopen, then open Radio/a smart playlist. Results should appear
  from disk. Within 30 minutes no scan is required; an overdue scan runs behind
  the usable list. Play while syncing, interrupt the network, and confirm the
  cached list remains available. Refresh still requests full reconciliation.
- Count a listen, wait a second and restart. The song's local activity should
  remain without a rescan or replaying the scrobble. Switch server/user and check
  isolation. A first-ever install/cache miss still needs a complete sync.
- On iPhone, scroll detailed covers/text beneath top/bottom glass, open a sheet
  and a popup, and rotate. Refraction should follow each rounded control edge,
  with a lightly frosted center and separate inner/outer glints. Check a menu over another
  glass surface for feedback artifacts. Windows retains blur plus the layered
  rim because its renderer lacks ImageFilter.shader support. Reduce Transparency
  and high contrast must still give an opaque surface.
- A rendered shader regression verifies a translated lens over a striped image;
  widget previews cover five viewport/theme combinations. Physical-device
  Impeller compositing and large-library responsiveness still need sideload checks.

Technical references: Flutter's ImageFilter.shader requires a texture-size uniform
and input sampler; that texture size is not the widget's shape bounds. Shape
coordinates now update during scene composition (including retained transforms),
and the filter no longer composes a padded
blur before refraction. A quarter-circle bevel displaces the background inward,
while directional outer/inner strokes provide separation on every renderer.
[Flutter shader API](https://api.flutter.dev/flutter/dart-ui/ImageFilter/ImageFilter.shader.html),
[Flutter runtime filter source](https://github.com/flutter/flutter/blob/master/engine/src/flutter/impeller/entity/contents/filters/runtime_effect_filter_contents.cc),
[Liquid Glass Renderer refraction model](https://pub.dev/packages/liquid_glass_renderer#refraction).

### Queue glass boundary follow-up (IMG_7065)

The refraction shader now passes exterior pixels through unchanged, including
rounded-corner cutouts; previously those pixels received maximum distortion and
relied solely on the widget clip. Refraction is confined to an 8-point bevel with
at most 8 points of displacement (previously 14/30). Every lens/diffusion sample is
projected inside the rounded panel so neighboring rows cannot enter through the
rim. A normalized 5-by-5 Gaussian replaces the cross-shaped five-sample diffusion.
Shared glass adds a 12% neutral frost wash in both themes. The captured backdrop
uses source replacement to avoid blending it over itself inside opacity layers,
following [Flutter's backdrop blending guidance](https://api.flutter.dev/flutter/widgets/BackdropFilter-class.html).

Check Up Next over detailed album art: the first upcoming song should not appear
as an extra strip beyond the header, and outside corners/borders should remain
undistorted. Scroll under the pinned header, open its menu, and rotate. Inspect
light/dark labels and Reduce Transparency. Rendered regressions exercise the
shader without an external clip, adjacent-color isolation at every rounded edge,
and diffusion of fine detail; device compositing remains a sideload check.
