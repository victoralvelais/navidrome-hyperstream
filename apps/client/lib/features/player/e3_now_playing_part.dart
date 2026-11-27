part of 'player_controls.dart';

/// E3's presentation wired directly to Hyperstream's single playback service.
/// No demo player, timers, volume or queue state is duplicated here.
class _NowPlaying extends StatefulWidget {
  const _NowPlaying({
    required this.playback,
    required this.client,
    this.collections,
    this.onAlbum,
    this.onArtist,
    this.showCamera = true,
  });
  final PlaybackService playback;
  final NavidromeClient client;
  final LibraryCollections? collections;
  final ValueChanged<Album>? onAlbum;
  final ValueChanged<Artist>? onArtist;
  final bool showCamera;
  @override
  State<_NowPlaying> createState() => _NowPlayingState();
}

class _NowPlayingState extends State<_NowPlaying> {
  PlaybackService get playback => widget.playback;
  final _snapshotKey = GlobalKey();
  bool _sharing = false;

  void _visitLibrary(VoidCallback action) {
    final route = ModalRoute.of(context);
    Navigator.of(context).popUntil((candidate) => candidate == route);
    Navigator.pop(context);
    action();
  }

  Widget _actions(Track track) => NowPlayingTrackActions(
    song: track,
    playback: playback,
    collections: widget.collections!,
    onAlbum: widget.onAlbum == null
        ? null
        : (album) => _visitLibrary(() => widget.onAlbum!(album)),
    onArtist: widget.onArtist == null
        ? null
        : (artist) => _visitLibrary(() => widget.onArtist!(artist)),
  );

  void _queue(BuildContext context) => showGlassSheet<void>(
    context: context,
    pullFromList: true,
    padBottomSafeArea: false,
    builder: (_) => _QueuePage(
      playback: playback,
      client: widget.client,
      collections: widget.collections,
      trackActions: _actions,
    ),
  );

  Future<void> _snapshot() async {
    if (_sharing) return;
    _sharing = true;
    try {
      // Capture the cover/title card only. Native AirPlay views and private
      // provider diagnostics must never appear in the shared image.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final boundary =
          _snapshotKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(
        pixelRatio: (1200 / boundary.size.width).clamp(1.0, 3.0),
      );
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null || !mounted) return;
        final saved = await PlayerSnapshot.share(data.buffer.asUint8List());
        if (mounted && saved) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Snapshot saved to Downloads.')),
          );
        }
      } finally {
        image.dispose();
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not share this snapshot. Try again.'),
          ),
        );
      }
    } finally {
      _sharing = false;
    }
  }

  Future<void> _more(BuildContext playerContext) async {
    final action = await showGlassSheet<String>(
      context: playerContext,
      useSafeArea: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: .85,
        child: _PlaybackView(
          playback: playback,
          builder: (context, item, state) {
            final track = playback.trackAt(state.queueIndex ?? -1);
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Playback & song',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close more',
                          onPressed: () => Navigator.pop(context),
                          icon: const AppIcon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  TempoControls(playback: playback),
                  const Divider(indent: 16, endIndent: 16),
                  ValueListenableBuilder<SleepTimerState?>(
                    valueListenable: playback.sleepTimer,
                    builder: (context, timer, _) => ListTile(
                      leading: const AppIcon(Icons.bedtime_outlined),
                      title: const Text('Sleep timer'),
                      subtitle: timer == null
                          ? const Text('Off')
                          : _SleepStatus(playback: playback),
                      onTap: item == null
                          ? null
                          : () => showSleepTimer(context, playback),
                    ),
                  ),
                  if (track != null)
                    ListTile(
                      title: const Text('Save to remote folder'),
                      subtitle: Text(
                        track.source == null
                            ? 'Send this library song'
                            : 'Download or view save status',
                      ),
                      trailing: track.source != null
                          ? SourceDownloadButton(
                              key: ValueKey(track.id),
                              client: widget.client,
                              tracks: [track],
                            )
                          : IconButton(
                              tooltip: 'Send song to remote folder',
                              icon: const AppIcon(Icons.download_rounded),
                              onPressed: () => sendSongToRemote(
                                context,
                                widget.client,
                                track,
                              ),
                            ),
                    ),
                  if (PlayerSnapshot.supported)
                    ListTile(
                      leading: const AppIcon(Icons.ios_share_rounded),
                      title: const Text('Share snapshot'),
                      subtitle: const Text('Artwork and song title'),
                      onTap: item == null
                          ? null
                          : () => Navigator.pop(context, 'snapshot'),
                    ),
                  if (widget.showCamera && CameraService.supported)
                    ListTile(
                      leading: const AppIcon(Icons.photo_camera_outlined),
                      title: const Text('Camera'),
                      onTap: () => Navigator.pop(context, 'camera'),
                    ),
                  if (track != null &&
                      track.source == null &&
                      widget.collections != null)
                    ListTile(
                      title: const Text('Song actions'),
                      trailing: _actions(track),
                    ),
                  ListTile(
                    leading: const AppIcon(Icons.info_outline_rounded),
                    title: const Text('Playback details'),
                    onTap: () => _showPlaybackDiagnostics(context, playback),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'snapshot') {
      await _snapshot();
    } else if (action == 'camera') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CameraPage(
            playback: playback,
            client: widget.client,
            collections: widget.collections,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: 1,
    child: Semantics(
      label: 'Music player',
      onDismiss: () => Navigator.pop(context),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.maybePop(context),
        },
        child: Focus(
          autofocus: true,
          child: EdgeBackGesture(
            onBack: () => Navigator.pop(context),
            child: _PlaybackView(
              playback: playback,
              builder: (context, item, state) => PlayerArtwork(
                client: widget.client,
                coverArt: item?.extras?['coverArtId'] as String?,
                externalUri: publicArtwork(item?.extras?['sourceArtwork']),
                builder: (context, image, palette) {
                  final theme = Theme.of(context);
                  // This art-led canvas is intentionally dark in either app theme.
                  // Preserve the user's font and icon family, and adapt only contrast.
                  final scheme =
                      ColorScheme.fromSeed(
                        seedColor: palette.accent,
                        brightness: Brightness.dark,
                      ).copyWith(
                        primary: palette.accent,
                        surface: palette.deep,
                        onSurface: Colors.white,
                      );
                  return Theme(
                    data: hyperstreamTheme(Brightness.dark).copyWith(
                      platform: theme.platform,
                      visualDensity: theme.visualDensity,
                      colorScheme: scheme,
                      iconTheme: theme.iconTheme.copyWith(color: Colors.white),
                      iconButtonTheme: IconButtonThemeData(
                        style: IconButton.styleFrom(
                          foregroundColor: Colors.white,
                          disabledForegroundColor: Colors.white38,
                        ),
                      ),
                      textTheme: theme.textTheme.apply(
                        bodyColor: Colors.white,
                        displayColor: Colors.white,
                      ),
                    ),
                    child: Builder(
                      builder: (context) =>
                          _page(context, item, state, image, palette),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _page(
    BuildContext context,
    MediaItem? item,
    PlaybackState state,
    ImageProvider? image,
    AlbumPalette palette,
  ) {
    final effects = GlassScope.effectsEnabled(context);
    final running =
        state.playing &&
        state.processingState == AudioProcessingState.ready &&
        !MediaQuery.disableAnimationsOf(context) &&
        effects &&
        TickerMode.valuesOf(context).enabled &&
        ModalRoute.of(context)?.isCurrent != false;
    final track = playback.trackAt(state.queueIndex ?? -1);
    final favorite =
        track != null && track.source == null && widget.collections != null
        ? SizedBox.square(
            dimension: 48,
            child: FavoriteButton(
              collections: widget.collections!,
              song: track,
            ),
          )
        : null;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: palette.deep,
        body: ClipRect(
          child: Stack(
            children: [
              if (effects)
                Positioned.fill(
                  child: AuroraBackground(
                    key: const ValueKey('now-playing-aurora'),
                    palette: palette,
                    running: running,
                  ),
                ),
              if (effects && image != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                      child: LayoutBuilder(
                        builder: (context, bounds) =>
                            bounds.maxWidth < 700 &&
                                bounds.maxHeight > bounds.maxWidth
                            ? Stack(
                                children: [
                                  Positioned(
                                    top: bounds.maxWidth * .75,
                                    left: 0,
                                    right: 0,
                                    bottom: 0,
                                    child: _E3Reflection(image: image),
                                  ),
                                ],
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              LayoutBuilder(
                builder: (context, bounds) {
                  final wide = bounds.maxWidth >= 700;
                  final bottom = MediaQuery.paddingOf(context).bottom + 16;
                  Widget cover(double size) => RepaintBoundary(
                    key: _snapshotKey,
                    child: _E3Cover(
                      image: image,
                      palette: palette,
                      item: item,
                      size: size,
                      running: running,
                      favorite: favorite,
                    ),
                  );
                  Widget controls(double minHeight) => ConstrainedBox(
                    constraints: BoxConstraints(minHeight: minHeight),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _E3SeekBar(
                            key: ValueKey(item?.id),
                            playback: playback,
                            item: item,
                            state: state,
                            palette: palette,
                            running: running,
                          ),
                          const SizedBox(height: 12),
                          _transport(state, item, palette, running),
                          const SizedBox(height: 14),
                          _bottomBar(context, state, palette),
                          _PlayerErrors(playback: playback, state: state),
                        ],
                      ),
                    ),
                  );
                  if (wide) {
                    final coverSize = (bounds.maxWidth * .49).clamp(
                      280.0,
                      520.0,
                    );
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: bounds.maxHeight,
                        ),
                        child: Padding(
                          padding: EdgeInsets.only(
                            top: MediaQuery.paddingOf(context).top + 66,
                            bottom: bottom,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: coverSize,
                                child: cover(coverSize),
                              ),
                              Expanded(child: controls(coverSize)),
                            ],
                          ),
                        ),
                      ),
                    );
                  }
                  return SingleChildScrollView(
                    key: const ValueKey('now-playing-scroll'),
                    child: Padding(
                      padding: EdgeInsets.only(bottom: bottom),
                      child: Column(
                        children: [
                          cover(bounds.maxWidth),
                          controls(
                            (bounds.maxHeight - bounds.maxWidth - bottom).clamp(
                              0.0,
                              double.infinity,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                    child: Row(
                      children: [
                        GlassSurface(
                          child: IconButton(
                            tooltip: 'Close player',
                            onPressed: () => Navigator.pop(context),
                            icon: const AppIcon(
                              Icons.keyboard_arrow_down_rounded,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 300),
                              child: GlassSurface(
                                radius: 18,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  child: DefaultTextStyle(
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall!
                                        .copyWith(color: Colors.white),
                                    child: _AudioDetails(item: item),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        GlassSurface(
                          child: IconButton(
                            tooltip: 'Show queue',
                            onPressed: () => _queue(context),
                            icon: const AppIcon(Icons.queue_music_rounded),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _transport(
    PlaybackState state,
    MediaItem? item,
    AlbumPalette palette,
    bool running,
  ) {
    final shuffle = state.shuffleMode != AudioServiceShuffleMode.none;
    final busy = state.processingState == AudioProcessingState.loading;
    final repeat = state.repeatMode;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          tooltip: shuffle ? 'Turn shuffle off' : 'Shuffle queue',
          isSelected: shuffle,
          color: shuffle ? palette.accent : Colors.white70,
          onPressed: item == null || busy
              ? null
              : () => playback.setShuffleMode(
                  shuffle
                      ? AudioServiceShuffleMode.none
                      : AudioServiceShuffleMode.all,
                ),
          icon: const AppIcon(Icons.shuffle_rounded),
        ),
        SizedBox(
          width: 52,
          height: 56,
          child: _Previous(playback: playback, state: state, large: true),
        ),
        PulsePlayButton(
          playing: state.playing,
          running: running,
          palette: palette,
          busy:
              !MediaQuery.disableAnimationsOf(context) &&
              [
                AudioProcessingState.loading,
                AudioProcessingState.buffering,
              ].contains(state.processingState),
          onPressed: item == null && !playback.canRetryPlayback
              ? null
              : state.playing
              ? playback.pause
              : playback.play,
        ),
        SizedBox(
          width: 52,
          height: 56,
          child: _Next(playback: playback, state: state, large: true),
        ),
        IconButton(
          tooltip: switch (repeat) {
            AudioServiceRepeatMode.none => 'Repeat off',
            AudioServiceRepeatMode.one => 'Repeat one',
            _ => 'Repeat all',
          },
          isSelected: repeat != AudioServiceRepeatMode.none,
          color: repeat == AudioServiceRepeatMode.none
              ? Colors.white70
              : palette.accent,
          onPressed: item == null || busy
              ? null
              : () => playback.setRepeatMode(switch (repeat) {
                  AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
                  AudioServiceRepeatMode.all => AudioServiceRepeatMode.one,
                  _ => AudioServiceRepeatMode.none,
                }),
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const AppIcon(Icons.repeat_rounded),
              if (repeat == AudioServiceRepeatMode.one)
                Positioned(
                  right: -5,
                  top: -7,
                  child: Text(
                    '1',
                    style: TextStyle(
                      fontSize: 10,
                      color: palette.accent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bottomBar(
    BuildContext context,
    PlaybackState state,
    AlbumPalette palette,
  ) => GlassSurface(
    child: SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.only(left: 4, right: 4),
        child: Row(
          children: [
            ListenableBuilder(
              listenable: playback.preferences,
              builder: (context, _) => IconButton(
                tooltip: playback.preferences.volume == 0
                    ? 'Unmute music'
                    : 'Mute music',
                onPressed: playback.toggleMute,
                icon: AppIcon(
                  playback.preferences.volume == 0
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                  size: 18,
                ),
              ),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: playback.preferences,
                builder: (context, _) => GlowSlider(
                  key: const ValueKey('now-playing-volume'),
                  value: playback.preferences.volume,
                  onChanged: playback.setAppVolume,
                  palette: palette,
                  label: 'Music volume',
                ),
              ),
            ),
            const SizedBox(width: 6),
            const OutputButton(),
            Badge(
              isLabelVisible: (state.speed - 1).abs() >= .001,
              label: Text('${state.speed.toStringAsFixed(2)}×'),
              backgroundColor: palette.accent,
              textColor: Colors.black,
              child: IconButton(
                tooltip: 'More playback options',
                onPressed: () => _more(context),
                icon: const AppIcon(Icons.more_horiz_rounded),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _E3Cover extends StatelessWidget {
  const _E3Cover({
    required this.image,
    required this.palette,
    required this.item,
    required this.size,
    required this.running,
    this.favorite,
  });
  final ImageProvider? image;
  final AlbumPalette palette;
  final MediaItem? item;
  final double size;
  final bool running;
  final Widget? favorite;
  @override
  Widget build(BuildContext context) {
    Widget placeholder() => ColoredBox(
      color: palette.deep,
      child: Center(
        child: AppIcon(
          Icons.album_outlined,
          size: size * .25,
          color: palette.accent.withValues(alpha: .5),
        ),
      ),
    );
    final scaler = MediaQuery.textScalerOf(context);
    final height =
        (MediaQuery.paddingOf(context).top +
                60 +
                scaler.scale(42) * 2.1 +
                scaler.scale(15) * 2 +
                38)
            .clamp(size, double.infinity);
    return SizedBox(
      width: size,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: palette.deep),
          if (image != null &&
              height > size &&
              GlassScope.effectsEnabled(context))
            _E3Reflection(image: image!),
          Positioned(
            top: 0,
            left: 0,
            width: size,
            height: size,
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black, Colors.black, Colors.transparent],
                stops: [0, .72, 1],
              ).createShader(rect),
              child: AnimatedSwitcher(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 450),
                child: image == null
                    ? placeholder()
                    : Image(
                        key: ValueKey(image),
                        image: image!,
                        fit: BoxFit.cover,
                        width: size,
                        height: size,
                        excludeFromSemantics: true,
                        errorBuilder: (_, _, _) => placeholder(),
                      ),
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x18000000),
                  Colors.transparent,
                  Color(0xBF000000),
                ],
                stops: [0, .35, 1],
              ),
            ),
          ),
          ClipRect(child: SheenSweep(running: running)),
          Positioned(
            left: 22,
            right: 22,
            bottom: 14,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item?.title ?? 'Not playing',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 42,
                          height: 1.05,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -1.3,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              color: Colors.black54,
                              blurRadius: 18,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item?.artist ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                ?favorite,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _E3Reflection extends StatelessWidget {
  const _E3Reflection({required this.image});
  final ImageProvider image;
  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: ClipRect(
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black, Colors.transparent],
          stops: [0, .3, 1],
        ).createShader(rect),
        child: Opacity(
          opacity: .55,
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 46, sigmaY: 46),
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.diagonal3Values(1.3, -1.3, 1),
              child: Image(
                image: image,
                fit: BoxFit.cover,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _E3SeekBar extends StatefulWidget {
  const _E3SeekBar({
    super.key,
    required this.playback,
    required this.item,
    required this.state,
    required this.palette,
    required this.running,
  });
  final PlaybackService playback;
  final MediaItem? item;
  final PlaybackState state;
  final AlbumPalette palette;
  final bool running;
  @override
  State<_E3SeekBar> createState() => _E3SeekBarState();
}

class _E3SeekBarState extends State<_E3SeekBar> {
  double? _drag;
  @override
  Widget build(BuildContext context) => StreamBuilder<Duration>(
    stream: widget.playback.positionStream,
    initialData: widget.playback.position,
    builder: (context, snapshot) {
      final duration = widget.item?.duration ?? Duration.zero;
      final max = duration.inMilliseconds.toDouble();
      final value =
          (_drag ?? (snapshot.data ?? Duration.zero).inMilliseconds.toDouble())
              .clamp(0.0, max > 0 ? max : 1.0);
      final enabled =
          max > 0 && widget.state.processingState == AudioProcessingState.ready;
      return Column(
        children: [
          GlowSlider(
            value: max > 0 ? value / max : 0,
            palette: widget.palette,
            label: 'Song position',
            shimmer: true,
            running: widget.running,
            semanticFormatter: (fraction) =>
                '${_time(Duration(milliseconds: (fraction * max).round()))} of ${_time(duration)}',
            onChanged: enabled
                ? (fraction) => setState(() => _drag = fraction * max)
                : null,
            onChangeEnd: enabled
                ? (fraction) async {
                    await widget.playback.seek(
                      Duration(milliseconds: (fraction * max).round()),
                    );
                    if (mounted) setState(() => _drag = null);
                  }
                : null,
          ),
          DefaultTextStyle(
            style: Theme.of(context).textTheme.labelMedium!.copyWith(
              fontSize: 12,
              color: Colors.white60,
              fontFeatures: const [ui.FontFeature.tabularFigures()],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_time(Duration(milliseconds: value.round()))),
                Text(
                  '-${_time(duration - Duration(milliseconds: value.round()))}',
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}
