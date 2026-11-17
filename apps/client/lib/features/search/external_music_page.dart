import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/library.dart';
import '../../services/music_provider.dart';
import '../../services/music_sources.dart';
import '../../services/navidrome_client.dart';
import '../../services/playback_service.dart';
import '../../widgets/floating_chrome.dart';
import '../../widgets/glass_surface.dart';
import '../../widgets/pull_to_refresh.dart';
import '../library/cover_art.dart';
import '../player/player_controls.dart';
import '../settings/music_source_settings.dart';
import 'source_import_action.dart';

class ExternalMusicPage extends StatefulWidget {
  const ExternalMusicPage({
    super.key,
    required this.client,
    required this.playback,
    this.album,
    this.sources,
    this.searchQuery,
    this.refreshRevision = 0,
  });
  final NavidromeClient client;
  final PlaybackService playback;
  final SourceAlbum? album;
  final MusicSources? sources;

  /// When supplied, render slivers under the shared library search controls.
  final String? searchQuery;
  final int refreshRevision;
  @override
  State<ExternalMusicPage> createState() => _ExternalMusicPageState();
}

class _ExternalMusicPageState extends State<ExternalMusicPage> {
  late final MusicSources sources = widget.sources ?? MusicSources.instance;
  final query = TextEditingController();
  MusicProvider? provider;
  Timer? debounce;
  int revision = 0;
  bool busy = false;
  String? error;
  List<Track> tracks = [];
  List<SourceAlbum> albums = [];

  @override
  void initState() {
    super.initState();
    query.text = widget.searchQuery ?? '';
    sources.addListener(_sourceChanged);
    _sourceChanged();
  }

  @override
  void didUpdateWidget(covariant ExternalMusicPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchQuery != oldWidget.searchQuery) {
      query.text = widget.searchQuery ?? '';
      _changed(query.text);
    } else if (widget.refreshRevision != oldWidget.refreshRevision) {
      unawaited(_load());
    }
  }

  void _sourceChanged() {
    ++revision;
    debounce?.cancel();
    provider?.close();
    try {
      provider = sources.hasProviders
          ? sources.providerById(widget.album?.sourceId)
          : null;
    } on SourceException {
      provider = null;
    }
    setState(() {
      tracks = [];
      albums = [];
      error = sources.error;
      busy = false;
    });
    if (provider != null &&
        (widget.album != null || query.text.trim().isNotEmpty)) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    debounce?.cancel();
    final source = provider;
    if (source == null) return;
    final current = ++revision;
    final text = query.text.trim();
    if (widget.album == null && text.isEmpty) {
      setState(() {
        tracks = [];
        albums = [];
        busy = false;
        error = null;
      });
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final album = widget.album;
      Future<SourceSearch> load() async => album == null
          ? await source.search(text)
          : SourceSearch(tracks: await source.album(album), albums: const []);
      final result = sources.extensions == null
          ? await load()
          : await sources.extensions!.withVerification(
              load,
              isCurrent: () => mounted && current == revision,
            );
      if (!mounted || current != revision) return;
      setState(() {
        tracks = result.tracks;
        albums = result.albums;
      });
    } on Object catch (failure) {
      if (mounted && current == revision) {
        setState(
          () => error = failure is SourceException
              ? failure.message
              : 'This source could not load. Try again.',
        );
      }
    } finally {
      if (mounted && current == revision) setState(() => busy = false);
    }
  }

  void _changed(String _) {
    ++revision;
    debounce?.cancel();
    setState(() {
      tracks = [];
      albums = [];
      error = null;
      busy = query.text.trim().isNotEmpty;
    });
    debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  @override
  void dispose() {
    ++revision;
    sources.removeListener(_sourceChanged);
    debounce?.cancel();
    query.dispose();
    provider?.close();
    super.dispose();
  }

  Future<void> _settings() => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Music sources')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: MusicSourceSettings(sources: sources),
        ),
      ),
    ),
  );

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
    child: Text(text, style: Theme.of(context).textTheme.titleLarge),
  );

  Future<void> _play([Track? selected]) async {
    final available = tracks.where((track) => track.source!.available).toList();
    if (available.isEmpty) return;
    await widget.playback.playAlbum(
      widget.client,
      available,
      selected == null ? 0 : available.indexOf(selected),
    );
  }

  Widget? _sourcePicker() {
    return widget.album == null &&
            sources.extensions?.enabled.isNotEmpty == true
        ? Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: DropdownButtonFormField<String>(
              key: ValueKey(sources.selectedProvider),
              initialValue: sources.selectedProvider,
              decoration: const InputDecoration(
                labelText: 'Browse source',
                isDense: true,
              ),
              items: [
                for (final e in sources.extensions!.enabled)
                  DropdownMenuItem(value: e.id, child: Text(e.name)),
                if (sources.enabled)
                  DropdownMenuItem(
                    value: sources.sourceId,
                    child: const Text('Monochrome'),
                  ),
              ],
              onChanged: (id) async {
                if (id == null) return;
                try {
                  await sources.extensions!.choose(
                    catalog: id,
                    legacy: id == sources.sourceId,
                  );
                } on Object {
                  if (mounted) {
                    setState(
                      () => error =
                          'Could not change the music source. Try again.',
                    );
                  }
                }
              },
            ),
          )
        : null;
  }

  List<Widget> _results() => [
    if (!sources.hasProviders) ...[
      const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Enable a music source to search and play outside your library.',
        ),
      ),
      TextButton(onPressed: _settings, child: const Text('Music sources')),
    ] else if (widget.album == null && query.text.trim().isEmpty)
      const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Search songs and albums, or paste a public music link. Download the songs you like to your remote folder.',
        ),
      ),
    if (error != null)
      Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(error!),
            TextButton(
              onPressed: _settings,
              child: const Text('Music sources'),
            ),
            TextButton(
              onPressed: busy ? null : _load,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    if (widget.album case final album?) ...[
      Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            SizedBox(
              width: 220,
              child: CoverArt(
                client: widget.client,
                id: null,
                externalUri: album.artwork,
              ),
            ),
            const SizedBox(height: 16),
            Text(album.artist, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed:
                      !tracks.any((track) => track.source!.available) || busy
                      ? null
                      : _play,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Play'),
                ),
                const SizedBox(width: 16),
                SourceDownloadButton(client: widget.client, tracks: tracks),
              ],
            ),
          ],
        ),
      ),
    ],
    if (tracks.isNotEmpty) _heading('Songs'),
    for (final track in tracks)
      ListTile(
        enabled: track.source!.available,
        leading: SizedBox.square(
          dimension: 48,
          child: CoverArt(
            client: widget.client,
            id: null,
            externalUri: track.source?.artwork,
            radius: 10,
          ),
        ),
        title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          track.source!.available
              ? track.artist
              : '${track.artist} · Unavailable',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: track.source!.available ? () => _play(track) : null,
        trailing: SourceDownloadButton(client: widget.client, tracks: [track]),
      ),
    if (albums.isNotEmpty) _heading('Albums'),
    for (final album in albums)
      ListTile(
        leading: SizedBox.square(
          dimension: 56,
          child: CoverArt(
            client: widget.client,
            id: null,
            externalUri: album.artwork,
            radius: 12,
          ),
        ),
        title: Text(album.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          album.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => ExternalMusicPage(
              client: widget.client,
              playback: widget.playback,
              album: album,
              sources: sources,
            ),
          ),
        ),
      ),
    if (!busy &&
        error == null &&
        sources.hasProviders &&
        query.text.trim().isNotEmpty &&
        tracks.isEmpty &&
        albums.isEmpty)
      const Padding(
        padding: EdgeInsets.all(24),
        child: Text('No matches from this source.'),
      ),
  ];

  Widget _embedded() => SliverMainAxisGroup(
    slivers: [
      if (_sourcePicker() case final picker?) SliverToBoxAdapter(child: picker),
      if (busy) const SliverToBoxAdapter(child: LinearProgressIndicator()),
      SliverList.list(children: _results()),
    ],
  );

  @override
  Widget build(BuildContext context) => widget.searchQuery != null
      ? _embedded()
      : Scaffold(
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                FloatingTopBar(
                  title: widget.album?.title ?? 'Online',
                  leading: IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  ),
                  trailing: IconButton(
                    tooltip: 'Music sources',
                    onPressed: _settings,
                    icon: const Icon(Icons.tune_rounded),
                  ),
                ),
                ?_sourcePicker(),
                if (widget.album == null && sources.hasProviders)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                    child: GlassSurface(
                      radius: 28,
                      child: TextField(
                        controller: query,
                        onChanged: _changed,
                        onSubmitted: (_) {
                          FocusScope.of(context).unfocus();
                          _load();
                        },
                        autocorrect: false,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: sources.extensions?.selected != null
                              ? 'Search or paste a playlist link'
                              : 'Search Monochrome',
                          prefixIcon: const Icon(Icons.search_rounded),
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                        ),
                      ),
                    ),
                  ),
                if (busy) const LinearProgressIndicator(),
                Expanded(
                  child: PullToRefresh(
                    onRefresh: _load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.only(bottom: 20),
                      children: _results(),
                    ),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: PlayerControls(
                    playback: widget.playback,
                    client: widget.client,
                  ),
                ),
              ],
            ),
          ),
        );
}
