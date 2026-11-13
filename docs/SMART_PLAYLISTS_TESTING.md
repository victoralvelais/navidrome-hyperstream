# Smart playlists: device checks

This milestone adds selectable **Rules** and **Mix** editor types. It requires
only the existing Navidrome account. Addons and background updates
with the app closed are deferred. Automated tests use synthetic API responses;
real server metadata, large-library timing and device usability still need testing.

The variety follow-up ships in paired **0.1.0+42** packages from commit
`53aa00dbc897ed220973fe98a45b526fdcd15c79`:
[release workflow](https://github.com/victoralvelais/navidrome-hyperstream/actions/runs/43499609859).
It adds artist spacing, stable shuffle and persisted Reshuffle to Rules/Mix.
Built-in Recent Radio keeps its existing behavior. This build also includes the
playback recovery fixes; continue the [playback device checks](PLAYBACK_CONTINUITY_TESTING.md)
on the same installation.

Validation: all 284 Flutter tests pass, with clean formatting and static analysis.
Coverage includes saved/failed/concurrent reshuffles, legacy definitions, strict
and relaxed spacing across overlapping pools, a 20,000-track single-artist case,
and editor/preview/save flows at 320 px with enlarged text and desktop width.
Both release jobs passed their required checks. Downloaded package hashes, archive
integrity and the IPA's version/build were verified against the release manifest.
The Windows runner reported no audio output, so its audible playback check was
skipped; queue restoration checks still ran. The iOS simulator launch was not
requested. Physical-device acceptance remains open.

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

## Stable shuffle and artist spacing

1. Create/edit a custom **Rules** playlist. Choose **Order → Stable shuffle**,
   **Artist spacing → 3 other songs between repeats**, then Preview tracks.
   Use a broad enough selection to include at least four primary artists.
2. Play the result and note its order. Tap **Reshuffle**: the preview should change,
   while the playing queue stays unchanged. Save the editor. Reopen or restart;
   the saved seed/order should survive when eligible tracks/settings are unchanged.
3. On the saved playlist page, Reshuffle saves a new order immediately. Pulling to
   refresh or counting a listen must not roll a new shuffle or trigger an extra
   scan. Membership changes can still move tracks; the current queue stays intact.
4. In a **Mix**, edit a pool and choose Stable shuffle for that pool. Other pools
   may keep their own orders. Set artist spacing in the main editor, preview, and
   check it across pool boundaries. Requested and actual shares may differ when
   spacing or overlapping pools limits the possible selections.
5. Try a selection with only one or two artists. With **Relax spacing when
   necessary** on, the list continues and reports relaxed selections. Turn it off:
   the list should stop rather than break the spacing, with an explanation.
6. Use **Play** to hear the configured order and spacing. The separate transport
   **Shuffle** bypasses spacing, as the preview explains. Existing playlists keep
   spacing Off until edited; built-in Recent Radio is unchanged.

## Custom ranking

1. In Rules choose **Order → Custom ranking**. Leave the initial 60-point added,
   25-point played, 15-point favorite and 20-point play-count weights. Set added
   recency to 14 days and Preview. Each sample explains the four contributions.
2. Move a weight to 0 and preview again; that contribution disappears. Empty or
   invalid windows must prevent Preview/Save with an explanation. All weights at
   zero are valid and use track ID to break ties.
3. Save, reopen and confirm settings. Switch to Mix and give a pool different
   ranking weights/windows. Rules settings should survive switching back.
4. Count a listen or favorite a track. Scores should update without a library
   scan, while the current playing queue keeps its previous order. Artist spacing
   can move lower scores ahead; Mix shares still determine pool contributions.

## Genre, release year and rating

1. After one normal library refresh, create Include ALL: Genre contains Rock,
   Release year greater than 1999, My rating greater than 3. Preview and compare
   against tagged songs in Navidrome. Genres match every supplied song genre.
2. Try Genre does not contain Jazz: untagged songs must not silently qualify.
   Select Is missing or Is present to include/exclude missing genres/years explicitly.
   Year 0 or rating 6 must be rejected; rating 0 means unrated.
3. Rate a playing song 5 stars, then remove its rating. After each successful
   server response, rating-filtered playlists update without a scan. Restart and
   confirm metadata and the acknowledged rating survive.
4. Existing cached tracks may lack genre/year until the next 30-minute or manual
   refresh. Updating the app must not force a fresh full-library scan.

## Publish a server copy

1. Open a saved smart playlist, let its preview finish, and choose the corner menu
   **Publish to Navidrome**. Review the name/count, then Create server copy. Verify
   the complete song order in Navidrome or another client, including tracks past
   the 50-song preview. Your current queue must remain unchanged.
2. Edit the smart configuration or Reshuffle, then publish again. Update server
   copy must update the same server playlist ID. Relaunch and repeat. A same-named
   manual playlist must never be adopted or replaced implicitly.
3. Edit the server copy from another client. Publishing must stop for review.
   Keep server edits leaves it alone; Create separate copy preserves the existing
   one; Replace reviewed copy deliberately replaces its songs. Changes made again
   before the replacement must be rechecked. Rename/sharing metadata is preserved.
4. Interrupt an update. Retry must first read and verify whether it succeeded.
   If a create's response was lost, Check existing copies lets you explicitly
   select the matching playlist for full-order verification. The app must not
   silently create duplicates. Choosing a separate copy warns that it may duplicate
   a previously successful create.
5. Failed/incomplete library syncs, empty results, incomplete server responses,
   another owner's playlist and read-only native smart playlists must not cause
   replacement. Verify account isolation. Cancel during review makes no write.

Publication is manual; opening/listening/refreshing does not update the server
copy. Deleting a local definition leaves the server copy intact. These checks use
your real server; automated tests use synthetic responses and do not establish
physical-server compatibility. OpenSubsonic has no conditional compare-and-replace,
so another client's change between the final read and write remains a protocol
limitation. Avoid simultaneous editing during publication.

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
  overlays and the catalog itself persist in an account-scoped disk cache.
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
This revision added a 12% neutral frost wash; the IMG_7066 follow-up below raises
the shared baseline to 20%. The captured backdrop
uses source replacement to avoid blending it over itself inside opacity layers,
following [Flutter's backdrop blending guidance](https://api.flutter.dev/flutter/widgets/BackdropFilter-class.html).

Check Up Next over detailed album art: the first upcoming song should not appear
as an extra strip beyond the header, and outside corners/borders should remain
undistorted. Scroll under the pinned header, open its menu, and rotate. Inspect
light/dark labels and Reduce Transparency. Rendered regressions exercise the
shader without an external clip, adjacent-color isolation at every rounded edge,
and diffusion of fine detail; device compositing remains a sideload check.

### Now Playing controls and connected startup (IMG_7066)

- Shared panels now use a 20% neutral frost wash in both themes.
- Glass paints its filtered background behind a separate foreground subtree.
  The native iOS route picker no longer sits inside a shader/backdrop filter;
  Flutter's iOS platform-view composition has filter restrictions. The picker
  explicitly has a transparent, non-opaque native background and receives the
  current text and violet accent colors from Flutter.
  [Flutter iOS platform-view composition](https://docs.flutter.dev/platform-integration/ios/platform-views#composition-limitations).
- In Now Playing, verify that the output/volume pill picks up the same glass as
  the queue button in light and dark themes, rather than turning black. Open the
  native output picker, return, expand/drag volume, and switch themes. Native
  compositing still needs physical-device verification.
- After a successful server login/restore, stay on Home: the shared catalog
  should already start loading. A missing cache begins the first scan immediately;
  a fresh cache is reused and an overdue cache refreshes in the background. Open
  Radio or a smart playlist while loading: it must reuse that work. Check that
  browsing/playback stays responsive. No catalog work starts when signed out or
  when saved/new credentials are rejected. Switching/disconnecting cancels the
  previous screen's catalog and prevents late pages from publishing to another account.

Local validation: 187 Flutter tests pass, static analysis is clean, and the five
phone/tablet/desktop preview runs pass. Startup tests cover a cold scan on Home,
navigation sharing that request, fresh-cache reuse, cancellation on leaving the
account, and signed-out/rejected-login sessions remaining idle. The iOS picker
test checks theme colors, foreground interaction, and separation from the filter.

### Original frost, volume contrast, and queue pull-down (IMG_7067–7068)

The user clarified that the requested frost baseline is the version **before the
transparency changes**, not removal of frost or the later 12%/20% overlays. The
`79b7120` baseline is restored: dark tint alpha .46/.42, light .72/.56, and a
24-point Gaussian blur. On Impeller the frosted interior is clipped inside the
lens rim, so blur does not erase its refraction. This uses a separate filter
after refraction, preserving the shader's coordinate system; native controls
remain outside both filters. The lens band and maximum displacement increase
from 8 to 10 points. Exterior passthrough and rounded sample bounds remain.

The expanded volume slider keeps a dark empty track, light percentage, pale fill,
and dark speaker over the fill in both themes, matching IMG_7068. The collapsed
speaker still follows the surrounding theme.
Check full volume, low volume, mute/unmute, and theme changes while expanded.

Up Next now shares one list drag with the sheet. At the top, elastic list movement
tapers toward 28 points; after 56 points of finger travel, panel movement eases
in. Release after 120 points of panel travel dismisses it; a downward flick can
dismiss earlier once the panel has moved 32 points. Short/cancelled pulls return
to rest. Scrolled lists reach the top first, and reversing the drag returns the
panel before scrolling the list upward. Header dragging, Close, queue reordering,
and wheel scrolling keep their existing behavior. Check this on a physical iPhone
with empty, short, and long queues, including a pull started low in the list.

Local validation: 200 Flutter tests pass and static analysis is clean. The five
viewport flows pass, including list-driven dismissal in the actual phone queue.
Gesture regressions run with both iOS and Windows scroll behavior; volume tests
cover both themes. The final light-theme volume preview was recaptured after
fixing the expanded control's consistent dark track. Native Impeller refraction
and gesture feel still need a sideload check on the iPhone.

### Softer material transition and floating-player inset

The next follow-up requests a midpoint between 28 and 29, with a continuous
material rather than a visible frosted plate inside the lens. Apple's
[Materials guidance](https://developer.apple.com/design/human-interface-guidelines/materials)
and [Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/)
provide the design references: preserve the underlying content, use blur for
legibility, and let lensing and restrained highlights provide separation. The
following values are Hyperstream's approximation, not Apple's private recipe.

- Blur is 12 points for controls and 14 for larger sheets, down from 24. Tint
  alpha is .40/.36 in dark mode and .58/.47 in light mode, between the recent
  normal-control treatments. Rim highlights and shadows are quieter.
- The hard inner clip is gone. A rounded-distance mask blends the blur and tint
  from zero at the outer edge to full strength over 20 points (28 for sheets,
  scaled down for small controls). The 10-point bounded lens remains underneath.
- The alpha mask paints with `dstIn` **inside** the backdrop filter's layer,
  after its blur and tint; the result composites with `srcOver` onto the lens.
  A `ShaderMask` wrapping a backdrop filter would hide the original pixels from
  that filter, as explained by a Flutter engine contributor in
  [flutter/flutter#154801](https://github.com/flutter/flutter/issues/154801).
  Pixel tests verify actual blur, a continuous transition, and preservation of
  the backdrop in both themes. This avoids snapshots and extra dependencies.
- All foreground controls, including the iOS route picker, remain outside the
  filtering/masking subtree. Reduce Transparency/high contrast stay opaque.
- The compact floating player's leading inset increases from 8 to 18 points;
  the expanded bar uses 12, giving artwork and labels room away from the curve.
  This addresses `Screenshot 2026-11-12 at 2.11.27 PM.heic`.

Device checks: inspect a queue/menu over detailed artwork and scroll text under
the header. Look for a continuous frost transition rather than an inset plate,
readable labels, bounded refraction, and stable edges while dragging the queue.
Check the collapsed player with short/long titles in both themes. Native iPhone
refraction still requires sideload verification.

Local validation: 203 Flutter tests pass, static analysis is clean, and all five
preview flows pass. New rendered tests check that the small/large rounded mask
has no step at the former inner boundary, the center actually blurs fine detail,
and the backdrop remains visible through the mask in both themes. Phone previews
include the new compact-player inset.

### Lighter full-panel frost and covered AirPlay view

The follow-up for `Screenshot 2026-11-12 at 3.34.33 PM.heic` reduces the
material again and extends it across each full rounded panel. Blur is now
8 points for controls and 10 for prominent sheets; tint alpha is .28/.24 in
dark mode and .40/.32 in light mode. The inner fade mask and its shader asset
are removed. Bounded refraction, restrained rim highlights, artwork tint and
the opaque accessibility fallback remain. These values supersede the preceding
material settings; there is no separate clear band around the frosted interior.

The dark patch over the queue aligns with the underlying native AirPlay view.
Flutter documents restrictions on filtering embedded iOS platform views in its
[platform-view guidance](https://docs.flutter.dev/platform-integration/ios/platform-views).
The route picker is now unmounted while another Flutter route covers Now Playing,
including its closing animation, and while the local volume popover is open.
A Flutter AirPlay icon occupies the same slot beneath the overlay. The native
picker returns when uncovered. This avoids composing UIKit beneath the queue's
backdrop filter; changing opacity alone would leave the native view in place.

Regression checks cover full-panel blur and backdrop preservation in both themes,
native-view disposal beneath a sheet, nested dialogs, delayed restoration after
the closing transition, and local volume-overlay visibility. Physical iPhone
checks remain necessary for native composition: open/drag/close Up Next over the
AirPlay position, open nested queue options and the volume popover, and confirm
the native route chooser still opens after dismissal. Inspect the lighter frost
and bounded lens in both themes over detailed artwork.

Local validation: 203 Flutter tests pass, static analysis and formatting are
clean, and all five viewport preview flows pass. Light/dark phone queue and
player previews were inspected. These captures use Flutter's desktop test
renderer; they do not prove physical iOS platform-view composition or Impeller
refraction.

### Scroll-through controls and matching navigation glass

The follow-up references IMG_7071, IMG_7072 and IMG_7073. Shared blur is reduced
another step to 6 points for controls and 8 for prominent sheets. The full-panel
tint and bounded refraction from the preceding release remain.

Up Next now extends its list behind a glass playback footer. The footer's measured
height supplies trailing scroll space, including text scaling, sleep status and
playback messages, so the last track can move completely above the controls.
The footer also blocks taps in gaps between controls from selecting covered songs.
The current-track row, pinned queue options, reorder handles and pull-to-dismiss
behavior are retained.

Search uses a pinned sliver containing its title, glass search field and filters.
Discovery tiles and results scroll underneath instead of being clipped below a
separate column. The search header owns its top bar to avoid a duplicate page
title; detail pages retain the existing Back/navigation bar. The same editor
element moves between discovery and results so the first typed character does
not dismiss the keyboard or lose selection. Search pagination, query cancellation,
filter selection and the playlist song picker keep their existing behavior.

Home settings groups (including their subpages) and the Library category group
use the shared rounded glass surface. They inherit artwork tint, theme colors
and the opaque fallback when glass effects are disabled or high contrast is on.

Device checks: scroll a long queue beneath the seek/transport controls, then reach
and select its last track. Check reordering, pull-down dismissal and an active
sleep timer. Scroll discovery and search results beneath the search field, type
without keyboard interruption, and clear the query. Check Home/Library groups
in both themes and with glass disabled. Native iOS refraction still needs the
physical-device sideload check.

Validation: all 204 Flutter tests pass, formatting and static analysis are clean,
and five viewport preview flows pass. After adding the footer tap guard, all five
layout flows pass again with checks for covered rows and final-track reachability.
The new search regression verifies actual overlap and hit testing beneath the
field, continued typing/focus across discovery/results, and access to the final
result. Light/dark queue, scrolled discovery, Home and Library previews were
inspected; they use the desktop test renderer, not native iOS refraction.

### Background system artwork and the queue bottom safe area

IMG_7076 shows a remaining gap below the playback footer. The queue sheet now
extends its list and footer surface through the bottom safe area; only the
footer's interactive content is inset above the home indicator. This removes
the separate strip and square list edge below the rounded footer. Other sheets
keep their existing safe-area behavior. Phone layout checks now include a
34-point bottom inset and assert both the shared bottom edge and control clearance.

The report of artwork appearing only after reopening has a likely app-side cause:
system covers previously used `dart:ui` decode/readback to create a PNG. Flutter's
[Impeller encoding implementation](https://github.com/flutter/flutter/blob/master/engine/src/flutter/lib/ui/painting/image_encoding_impeller.cc)
can defer readback until GPU availability returns. This matches the symptom but
is not a physical-device trace or proof of a LiveContainer limitation.

iOS now converts downloaded cover bytes through Image I/O on a native utility
queue, without Flutter textures or frames, then publishes the same private local
PNG to audio_service. Image I/O bounds the thumbnail to 512 pixels and applies
orientation. The 8 MiB input limit, account-scoped cache, stale-item protection
and silent handling of missing/invalid artwork remain. Cache files are published
by rename only after their contents are complete. Windows retains its existing
decoder. No authenticated artwork URL is exposed to system metadata.

The Dart regression simulates a paused lifecycle and verifies native conversion,
deduplicated requests, local file publication/cache reuse and invalid-cover
handling. The Mac release job also compiles and runs the production converter
without Flutter: PNG/JPEG conversion, rotated JPEG, size bounds, malformed input
and a background utility worker. This does not simulate a locked physical iPhone.

Device check: play a queue with covers not yet cached, lock the phone, and advance
several tracks from the lock screen/Control Center without returning to Hyperstream.
Artwork should update after the cover request completes. Also test automatic
track advancement. Check the full queue bottom edge while scrolling in both
themes; controls must remain above the home indicator and the last row reachable.

Local validation: 205 Flutter tests pass, formatting/static analysis are clean,
and all five viewport preview flows pass with the new bottom-inset checks.
Light/dark phone queue previews were inspected. Native converter validation is
an additional required step of the paired release workflow.

The user subsequently confirmed that 0.1.0+33 fixes system album artwork on their
device.

### Account actions inside Servers

Home now contains Appearance, Playback and Servers. The Account section,
connected username/server details and Disconnect from server live under
Home > Servers, below the saved connections. Disconnect opens a glass dialog
naming the active server and explaining that it stops playback and removes that
saved connection from the device. Cancel has default keyboard focus; Cancel,
Escape/Back and outside dismissal do not invoke the disconnect callback.
Only the explicit Disconnect button continues. Duplicate prompts are blocked,
and a confirmation is ignored if the active account changes while it is open.
Existing server switching, removal and disconnect storage behavior are retained.

The existing five-viewport flows now check that Home has no account/disconnect
section, the moved controls are reachable in Servers, cancelling/dismissing
preserves playback and the account, and confirmation invokes disconnect once.

Validation: all 205 Flutter tests pass, formatting and static analysis are clean,
and all five viewport preview flows pass. Home, Servers and the confirmation
dialog were visually inspected, including the small phone with enlarged text.
The startup regression also verifies that Cancel preserves saved credentials
and only confirming Disconnect prevents account restoration on the next launch.

### Share the audio file on iOS

The now-playing song menu now has **Share audio file** on iOS. It downloads the
original track with OpenSubsonic `download`, shows a cancellable glass progress
dialog, then opens the native activity sheet with one typed local audio file.
MP3 stays MP3 and FLAC stays FLAC; no transcoding or companion service is involved.
The attachment uses an `Artist - Title.ext` filename. Windows retains its existing
copy-song-details action.

The streamed download uses a private, unique temporary directory, blocks
redirects, rejects HTTP/JSON/HTML errors and empty/truncated responses, and aborts
on Cancel or account closure. The original 0.1.0+35 implementation removed the
file after the iOS activity completion callback; the compatibility follow-up below
replaces this with deferred cleanup. Neither server credentials nor authenticated
URLs are passed to other apps. An iPad popover anchor accompanies the item.

Discord is the primary device acceptance case. Its
[attachment FAQ](https://support.discord.com/hc/en-us/articles/25444343291031-File-Attachments-FAQ)
lists MP3 support; its
[February 2026 patch notes](https://discord.com/blog/discord-patch-notes-february-4-2026)
also describe iOS share-sheet file fixes. Destination apps determine supported
formats, upload limits and available channels. Hyperstream cannot verify remote
delivery from the activity completion callback, and no Discord upload has been
performed by the automated tests.

Device check: play an MP3 below your Discord upload limit, open its song menu,
choose Share audio file, and select Discord (under More if needed). Choose a
channel/DM, send, and confirm the recipient gets a playable MP3 attachment with
the expected name and size. Also try Save to Files/AirDrop, native-sheet Cancel,
download Cancel, and sharing twice. Repeat on iPad to check the popover. If Discord
is absent or its extension fails, Save to Files then attach from Discord itself.

Validation: the full 225-test Flutter suite passes. Final formatting and static
analysis are clean, and all 39 targeted API/player/share regressions pass after
the final cleanup changes. These include real HTTP cancellation before headers
and during the body, account closure, idle timeouts, byte-preserving MP3/FLAC
exports, invalid responses, safe filenames, file lifetime across the native
bridge, and progress/cancel/error flows at 320 px with 1.4x text. iOS compilation
and paired packaging run in the release workflow; physical Discord delivery is
the remaining device acceptance check.

### Discord share-extension compatibility follow-up

Device evidence after 0.1.0+35: an approximately 11 MB MP3 plays in Files and
uploads successfully with Discord's own channel attachment button. Sharing the
same saved file from Apple's Files share sheet also fails. This isolates the
observed failure to the iOS-to-Discord share-extension route; it does not establish
a corrupt export or upload-size rejection. Save to Files, then attach using the
Discord + button, is the user-confirmed working route.

The compatibility change supplies an `NSItemProvider` with real audio data and
a file-copy representation, with the expected type and filename. This replaces
the custom item source which returned a URL while overriding the data UTI.
[Apple documents that override for NSData items](https://developer.apple.com/documentation/uikit/uiactivityitemsource/activityviewcontroller(_:datatypeidentifierforactivitytype:)).
The provider's data consumer gets audio bytes; its file consumer can receive an
OS-managed copy instead of depending on access to an app-private URL.
[Apple data representation API](https://developer.apple.com/documentation/foundation/nsitemprovider/registerdatarepresentation(fortypeidentifier:visibility:loadhandler:)),
[Apple file representation API](https://developer.apple.com/documentation/foundation/nsitemprovider/registerfilerepresentation(fortypeidentifier:fileoptions:visibility:loadhandler:)).

Files offered to the system now survive sheet dismissal and extension errors.
Exports older than one day are reclaimed on a later export. Downloads cancelled
before handoff and native errors that prevent presentation still remove their
temporary files immediately. Sheet completion is never treated as proof of
Discord delivery. The iPhone no longer configures a popover; only iPad does,
matching the Xcode 26 compatibility handling in
[share_plus](https://github.com/fluttercommunity/plus_plugins/blob/main/packages/share_plus/share_plus/ios/share_plus/Sources/share_plus/FPPSharePlusPlugin.m).

The native release check exercises the production provider with an 11 MB fixture
through data, file-copy, legacy-item and generic-data consumers, including the
filename/type and missing-file failure. Dart regressions cover delayed reads
after the sheet callback, preserving recent exports, expiry and native error
cleanup. This validates our handoff; it does not reproduce Discord's proprietary
extension. Retry the direct share on-device before calling that route fixed.

Local validation: 230 Flutter tests pass; formatting and static analysis are
clean. The native provider check is a required release-workflow step.

The user subsequently confirmed that direct Discord sharing still fails on
0.1.0+36. Do not describe the provider change as a confirmed Discord fix. The
same approximately 11 MB MP3 plays in Files, fails when shared from Files, and
uploads successfully through Discord's own + attachment button.

The user then confirmed that an MP3 under 5 MB also fails when shared from Files
to the same channel, and Discord is the normal App Store installation. This
rules out an 11 MB-only threshold and Discord running inside LiveContainer as
explanations. The evidence points to the Discord/iOS share-extension route,
independently of Hyperstream's item provider; the exact failure inside that
extension remains unobserved. Do not keep changing attachment representations or
lowering audio quality without new evidence. The working route remains Save to
Files followed by Discord's own + attachment button. This update records device
evidence only and does not change the app or produce a new sideload build.

### Further Discord sharing research (2026-11-12)

The Files failure remains the baseline. Further research did not establish a
reliable Hyperstream-side fix for the App Store Discord share extension. Its
internal error is still unknown; do not present this as a proven root cause or
claim that the existing provider tests demonstrate successful Discord delivery.

The open-source
[ShareToDiscord extension](https://github.com/castdrian/ShareToDiscord/blob/main/Share/ShareViewController.swift)
forwards attachment URLs through `discord://share`. However,
[Unbound bundles a replacement extension with its modified client](https://unbound.rip/docs/user/ios-extensions).
This is not evidence that Hyperstream can hand an app-private file URL directly
to stock Discord. Apple documents that even an extension and its containing app
[need explicit shared-container access](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionScenarios.html).
Do not add the undocumented URL route as a verified workaround or require a
modified Discord installation.

A supported alternative for a future optional integration is a channel webhook.
[Discord's webhook API](https://docs.discord.com/developers/resources/webhook#execute-webhook)
accepts actual file bytes using multipart `files[n]`; `wait=true` requests server
confirmation and the created message. Hyperstream could upload directly without
Docker or the iOS share extension. Each destination needs a configured webhook,
created by someone with Manage Webhooks permission. Messages use the webhook
identity; this does not provide personal-account sharing to arbitrary channels
or DMs. Treat the webhook URL as a secret if implemented. This remains a proposal:
no integration was added and no Discord message was sent during this research.

Keep the confirmed Save to Files -> Discord + attachment workaround. No further
app changes or release were warranted by these findings; 0.1.0+36 remains the
latest sideload build. Future investigation needs new device evidence, such as
an extension error log or a confirmed working stock-Discord handoff, before
another compatibility build.
