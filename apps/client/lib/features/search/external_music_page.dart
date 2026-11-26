import 'package:hyperstream_client/widgets/app_icon.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/library.dart';
import '../../services/music_provider.dart';
import '../../services/music_sources.dart';
import '../../services/online_search.dart';
import '../../services/navidrome_client.dart';
import '../../services/playback_service.dart';
import '../../widgets/floating_chrome.dart';
import '../../widgets/glass_surface.dart';
import '../../widgets/pull_to_refresh.dart';
import '../../widgets/music_source_icon.dart';
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
    this.showTracks = true,
    this.showAlbums = true,
  });
  final NavidromeClient client;
  final PlaybackService playback;
  final SourceAlbum? album;
  final MusicSources? sources;

  /// When supplied, render slivers under the shared library search controls.
  final String? searchQuery;
  final int refreshRevision;
  final bool showTracks;
  final bool showAlbums;
  @override
  State<ExternalMusicPage> createState() => _ExternalMusicPageState();
}

class _ExternalMusicPageState extends State<ExternalMusicPage> {
  late final MusicSources sources = widget.sources ?? MusicSources.instance;
  final query = TextEditingController();
  MusicProvider? provider;
  OnlineSearch? search;
  String? sourceSignature;
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
    final signature =
        '${widget.album?.sourceId ?? ''}|${sources.searchSignature}';
    if (sourceSignature == signature) return;
    sourceSignature = signature;
    ++revision;
    debounce?.cancel();
    _stopSearch();
    provider?.close();
    try {
      provider = sources.hasProviders && widget.album != null
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
    if (sources.hasProviders &&
        (widget.album != null || query.text.trim().isNotEmpty)) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    debounce?.cancel();
    _stopSearch();
    final source = provider;
    if (!sources.hasProviders) return;
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
    if (widget.album == null) {
      final session = OnlineSearch(sources, text);
      search = session;
      session.addListener(_searchUpdated);
      await session.start();
      return;
    }
    if (source == null) {
      setState(() {
        busy = false;
        error = 'Enable this collection’s source in Music sources.';
      });
      return;
    }
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
    _stopSearch();
    setState(() {
      tracks = [];
      albums = [];
      error = null;
      busy = query.text.trim().isNotEmpty;
    });
    debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  void _searchUpdated() {
    if (!mounted || search == null) return;
    setState(() {
      tracks = search!.tracks;
      albums = search!.albums;
      busy = search!.busy;
      error = search!.error;
    });
  }

  void _stopSearch() {
    search?.removeListener(_searchUpdated);
    search?.dispose();
    search = null;
  }

  @override
  void dispose() {
    ++revision;
    sources.removeListener(_sourceChanged);
    debounce?.cancel();
    _stopSearch();
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
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.w700),
    ),
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
              key: ValueKey(sources.searchSource),
              initialValue: sources.searchSource ?? '__all',
              decoration: const InputDecoration(
                labelText: 'Browse source',
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(
                  value: '__all',
                  child: Text('All sources'),
                ),
                for (final e in sources.onlineSources)
                  DropdownMenuItem(value: e.id, child: Text(e.name)),
              ],
              onChanged: (id) async {
                if (id == null) return;
                try {
                  await sources.chooseSearchSource(id == '__all' ? null : id);
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

  Widget _artwork(String sourceId, Uri? artwork, double size) =>
      SizedBox.square(
        dimension: size,
        child: CoverArt(
          client: widget.client,
          id: null,
          externalUri: artwork,
          radius: 10,
          sourceId: sourceId,
        ),
      );

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
                  icon: const AppIcon(Icons.play_arrow_rounded),
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
    if (widget.showTracks && tracks.isNotEmpty) _heading('Songs'),
    for (final track in widget.showTracks ? tracks : <Track>[])
      ListTile(
        enabled: track.source!.available,
        leading: _artwork(track.source!.sourceId, track.source?.artwork, 48),
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
    if (widget.showAlbums && albums.isNotEmpty) _heading('Albums'),
    for (final album in widget.showAlbums ? albums : <SourceAlbum>[])
      ListTile(
        leading: _artwork(album.sourceId, album.artwork, 56),
        title: Text(album.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          album.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const AppIcon(Icons.chevron_right_rounded),
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
    if (search case final session?) ...[
      if (session.pending.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Text(
            'Searching ${session.pending.map((s) => s.name).join(', ')}…',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      for (final issue in session.issues)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              MusicSourceIcon(
                sourceId: issue.source.id,
                name: issue.source.name,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${issue.source.name} ${issue.verificationProvider == null ? 'could not load results' : 'needs verification'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              TextButton(
                key: ValueKey('retry-source-${issue.source.id}'),
                onPressed: () => session.retry(issue),
                child: Text(
                  issue.verificationProvider == null ? 'Retry' : 'Verify',
                ),
              ),
            ],
          ),
        ),
    ],
    if (!busy &&
        error == null &&
        (search?.issues.isEmpty ?? true) &&
        sources.hasProviders &&
        query.text.trim().isNotEmpty &&
        (!widget.showTracks || tracks.isEmpty) &&
        (!widget.showAlbums || albums.isEmpty))
      const Padding(
        padding: EdgeInsets.all(24),
        child: Text('No online matches.'),
      ),
  ];

  Widget _embedded() => SliverMainAxisGroup(
    slivers: [
      if (widget.showTracks || widget.showAlbums) ...[
        SliverToBoxAdapter(child: _heading('Online · ${sources.searchLabel}')),
        if (busy) const SliverToBoxAdapter(child: LinearProgressIndicator()),
        SliverList.list(children: _results()),
      ],
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
                    icon: const AppIcon(Icons.arrow_back_ios_new_rounded),
                  ),
                  trailing: IconButton(
                    tooltip: 'Music sources',
                    onPressed: _settings,
                    icon: const AppIcon(Icons.tune_rounded),
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
                          hintText: 'Search or paste a playlist link',
                          prefixIcon: const AppIcon(Icons.search_rounded),
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
