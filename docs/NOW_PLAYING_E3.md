# Now Playing: E3

The user-supplied Flutter handoff is adapted into the existing Hyperstream
player. `features/player/e3_now_playing_part.dart` owns the screen composition;
`e3/` contains the album palette, artwork loader and visual components. The
handoff's demo controller and standalone app are not part of the application.
`PlaybackService` remains the only audio/queue/settings owner.

The portrait cover is square and full width, with the title and artist at its
lower edge. A blurred mirrored continuation and slowly moving aurora fill the
background. Wide layouts put the cover and controls side by side. Short windows
and larger text scroll. The canvas uses dark contrast in both app themes;
`AppIcon` retains the user's selected icon family, including Solar variants.
No new font or package is required.

The floating header contains Close, the actual audio provider with known quality,
and Queue. The primary row contains shuffle, previous/restart, play/pause, next,
and repeat. The glass bar below retains app-only volume, native output selection
and More. A non-default playback rate appears as a badge on More.

More reuses per-song tempo/pitch controls, sleep timer, remote save progress and
delivery receipts, camera, library song actions and playback diagnostics. External
tracks retain their current source/save behavior; this design does not invent a
separate external-favorites store. Library favorites remain on the cover.

Share snapshot captures only the cover/title card. iOS uses the existing native
file-share bridge and temporary sandbox, retaining files for delayed receivers
and reclaiming old snapshot exports after a day on a later export. Windows saves
a PNG into Downloads. No account details, stream URLs, diagnostics or native
output picker are included in the captured card.

Ambient orbit/drift, sheen and progress shimmer run only during ready playback.
Reduce Motion disables animation; high contrast or disabled glass effects omit
the aurora and reflected blur. Palette transitions last 800 ms unless motion is
disabled. Sliders use Flutter's accessible input handling and seek only when a
drag ends. Playback, source matching and import policies are unchanged.

Physical iOS animation performance, AirPlay presentation and native snapshot
sharing still require device testing after installing the release.
