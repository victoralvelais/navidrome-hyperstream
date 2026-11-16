part of 'player_controls.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({
    super.key,
    required this.playback,
    required this.client,
    this.camera,
  });
  final PlaybackService playback;
  final NavidromeClient client;
  final CameraService? camera;

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  late final CameraService camera = widget.camera ?? CameraService();
  bool _stream = false;
  bool _fullscreen = false;
  bool _controls = true;
  bool _fill = true;
  bool _song = true;
  bool _originalTempo = false;
  bool _leaving = false;
  Timer? _hideControls;

  @override
  void initState() {
    super.initState();
    unawaited(camera.open());
  }

  @override
  void dispose() {
    _hideControls?.cancel();
    unawaited(camera.close());
    if (widget.camera == null) camera.dispose();
    super.dispose();
  }

  Future<void> _leave() async {
    if (_fullscreen) {
      _hideControls?.cancel();
      setState(() => _fullscreen = false);
      return;
    }
    if (_leaving) return;
    await camera.close();
    if (!mounted) return;
    setState(() => _leaving = true);
    Navigator.of(context).pop();
  }

  void _showControls() {
    _hideControls?.cancel();
    setState(() => _controls = true);
    _hideControls = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _controls = false);
    });
  }

  void _enterFullscreen() {
    setState(() => _fullscreen = true);
    _showControls();
  }

  Future<void> _details() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        child: StatefulBuilder(
          builder: (context, update) => ListenableBuilder(
            listenable: camera,
            builder: (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Camera details',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 20),
                StreamBuilder<PlaybackState>(
                  stream: widget.playback.playbackState,
                  initialData: widget.playback.playbackState.value,
                  builder: (context, snapshot) {
                    final speed = snapshot.data?.speed ?? 1;
                    return Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Playback speed'),
                            TextButton(
                              onPressed: () => widget.playback.setSpeed(1),
                              child: Text('${speed.toStringAsFixed(2)}×'),
                            ),
                          ],
                        ),
                        Slider(
                          value: speed.clamp(.5, 2),
                          min: .5,
                          max: 2,
                          divisions: 150,
                          label: '${speed.toStringAsFixed(2)}×',
                          onChanged: widget.playback.mediaItem.value == null
                              ? null
                              : widget.playback.setSpeed,
                        ),
                      ],
                    );
                  },
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Finish at original song tempo'),
                  subtitle: const Text(
                    'Adjust the saved dance and soundtrack to the original tempo.',
                  ),
                  value: _originalTempo,
                  onChanged: camera.recording || camera.saving
                      ? null
                      : (value) {
                          setState(() => _originalTempo = value);
                          update(() {});
                        },
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Takes save to Photos with the music. The recording microphone is off.',
                  ),
                ),
                if (camera.pending > 0) ...[
                  FilledButton.tonalIcon(
                    onPressed: camera.recording || camera.saving
                        ? null
                        : camera.retry,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text('Retry saving (${camera.pending})'),
                  ),
                  TextButton(
                    onPressed: camera.recording || camera.saving
                        ? null
                        : camera.recoverVideo,
                    child: const Text('Recover original camera video'),
                  ),
                ],
                if (camera.report.isNotEmpty)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Latest audio report'),
                    children: [SelectableText(camera.report)],
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> _broadcast() async {
    _hideControls?.cancel();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Share your camera',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              const Text(
                'In TikTok, open LIVE → Mobile gaming → Go LIVE. Confirm Start Broadcast in iOS, then return here and open Full Screen.',
              ),
              const SizedBox(height: 16),
              const Text(
                'Use the iPhone broadcast control below for screen sharing and microphone settings. TikTok confirms when your audience can watch and may also control the microphone.',
              ),
              const SizedBox(height: 16),
              const Center(
                child: SizedBox(
                  width: 60,
                  height: 60,
                  child: UiKitView(
                    viewType: 'dev.hyperstream/broadcast_picker',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Host controls are visible to viewers while open. Tap the camera picture to hide them.',
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted && _fullscreen) _showControls();
  }

  Widget _preview() => LayoutBuilder(
    builder: (context, bounds) => ClipRect(
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (camera.texture != null)
              FittedBox(
                fit: _fullscreen && !_fill ? BoxFit.contain : BoxFit.cover,
                child: SizedBox(
                  width: 720 * camera.aspect,
                  height: 720,
                  child: Transform.flip(
                    flipX: camera.front && !_stream,
                    child: Texture(textureId: camera.texture!),
                  ),
                ),
              ),
            if (!camera.ready)
              const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            if (!_fullscreen)
              Positioned(
                top: 12,
                right: 12,
                child: GlassSurface(
                  child: IconButton(
                    tooltip: 'Switch camera',
                    onPressed:
                        camera.ready && !camera.recording && !camera.saving
                        ? camera.switchCamera
                        : null,
                    icon: const Icon(Icons.cameraswitch_outlined),
                  ),
                ),
              ),
            if (camera.recording)
              Positioned(
                top: 16,
                left: 16,
                child: Semantics(
                  liveRegion: true,
                  child: const Chip(
                    avatar: Icon(
                      Icons.circle,
                      color: Colors.redAccent,
                      size: 12,
                    ),
                    label: Text('Recording'),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _transport({bool labels = true}) => _PlaybackView(
    playback: widget.playback,
    builder: (context, item, state) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          if (labels) ...[
            SizedBox(
              width: 44,
              height: 44,
              child: CoverArt(
                client: widget.client,
                id: item?.extras?['coverArtId'] as String?,
                radius: 8,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: _TrackLabels(item: item)),
          ] else
            const Spacer(),
          _Previous(playback: widget.playback, state: state),
          _PlayButton(playback: widget.playback, item: item, state: state),
          _Next(playback: widget.playback, state: state),
          if (!labels) const Spacer(),
        ],
      ),
    ),
  );

  Widget _message() => camera.message.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Semantics(liveRegion: true, child: Text(camera.message)),
              ),
              if (camera.pending > 0)
                TextButton(
                  onPressed: camera.saving ? null : camera.retry,
                  child: const Text('Retry'),
                ),
              IconButton(
                tooltip: 'Dismiss message',
                onPressed: camera.dismissMessage,
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
        );

  Widget _header() => LayoutBuilder(
    builder: (context, bounds) {
      final back = TextButton.icon(
        onPressed: _leave,
        icon: const Icon(Icons.chevron_left),
        label: const Text('Music'),
      );
      final details = IconButton(
        onPressed: _details,
        tooltip: 'Camera details',
        icon: const Icon(Icons.tune),
      );
      final modes = SegmentedButton<bool>(
        showSelectedIcon: false,
        style: const ButtonStyle(
          minimumSize: WidgetStatePropertyAll(Size(0, 40)),
          padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
          visualDensity: VisualDensity.compact,
        ),
        segments: const [
          ButtonSegment(value: false, label: Text('Record')),
          ButtonSegment(value: true, label: Text('Stream')),
        ],
        selected: {_stream},
        onSelectionChanged: camera.recording || camera.saving
            ? null
            : (value) => setState(() => _stream = value.single),
      );
      if (bounds.maxWidth < 360 ||
          MediaQuery.textScalerOf(context).scale(1) > 1.2) {
        return Column(
          children: [
            Row(children: [back, const Spacer(), details]),
            modes,
          ],
        );
      }
      return Row(
        children: [
          back,
          Expanded(child: Center(child: modes)),
          details,
        ],
      );
    },
  );

  Widget _studio() => SafeArea(
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
          child: _header(),
        ),
        _message(),
        Expanded(child: _preview()),
        _transport(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
          child: _stream
              ? Column(
                  children: [
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: camera.ready ? _enterFullscreen : null,
                          icon: const Icon(Icons.fullscreen),
                          label: const Text('Full Screen'),
                        ),
                        TextButton(
                          onPressed: _broadcast,
                          child: const Text('TikTok setup'),
                        ),
                      ],
                    ),
                    if (camera.captured) const Text('Screen sharing active'),
                  ],
                )
              : SizedBox(
                  height: 84,
                  child: Center(
                    child: camera.saving
                        ? const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text('Saving take…'),
                            ],
                          )
                        : Semantics(
                            button: true,
                            label: camera.recording
                                ? 'Stop and save take'
                                : 'Start recording',
                            child: Tooltip(
                              message: camera.recording
                                  ? 'Stop and save take'
                                  : 'Start recording',
                              child: InkResponse(
                                onTap: !camera.ready
                                    ? null
                                    : camera.recording
                                    ? camera.stop
                                    : () => camera.start(
                                        originalTempo: _originalTempo,
                                      ),
                                radius: 44,
                                child: Container(
                                  width: 76,
                                  height: 76,
                                  padding: EdgeInsets.all(
                                    camera.recording ? 19 : 4,
                                  ),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 3,
                                    ),
                                  ),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    decoration: BoxDecoration(
                                      color: camera.ready
                                          ? Colors.redAccent
                                          : Colors.white24,
                                      borderRadius: BorderRadius.circular(
                                        camera.recording ? 5 : 36,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
        ),
      ],
    ),
  );

  Widget _fullScreen() => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () {
      if (_controls) {
        _hideControls?.cancel();
        setState(() => _controls = false);
      } else {
        _showControls();
      }
    },
    child: Stack(
      fit: StackFit.expand,
      children: [
        _preview(),
        if (_song)
          Positioned(
            left: 20,
            right: 20,
            bottom: MediaQuery.paddingOf(context).bottom + 18,
            child: IgnorePointer(
              child: _PlaybackView(
                playback: widget.playback,
                builder: (context, item, state) => Text(
                  '${item?.title ?? ''}${item?.artist == null ? '' : ' · ${item!.artist}'}${state.playing ? '' : ' · Paused'}',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(blurRadius: 8)],
                  ),
                ),
              ),
            ),
          ),
        if (_controls)
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: GlassSurface(
                  radius: 24,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.center,
                        children: [
                          TextButton.icon(
                            onPressed: _leave,
                            icon: const Icon(Icons.fullscreen_exit),
                            label: const Text('Exit'),
                          ),
                          TextButton(
                            onPressed: () => setState(() => _fill = !_fill),
                            child: Text(_fill ? 'Fit' : 'Fill'),
                          ),
                          TextButton(
                            onPressed: () => setState(() => _song = !_song),
                            child: Text(_song ? 'Hide song' : 'Show song'),
                          ),
                          TextButton.icon(
                            onPressed: _broadcast,
                            icon: const Icon(Icons.mic_none),
                            label: const Text('Mic'),
                          ),
                        ],
                      ),
                      _transport(labels: false),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: _leaving,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_leave());
    },
    child: Theme(
      data: Theme.of(context).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xffbc9be7),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xff101014),
      ),
      child: Scaffold(
        body: ListenableBuilder(
          listenable: camera,
          builder: (context, _) => _fullscreen ? _fullScreen() : _studio(),
        ),
      ),
    ),
  );
}
