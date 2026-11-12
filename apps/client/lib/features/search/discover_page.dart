import 'package:flutter/material.dart';

import '../../models/library.dart';
import '../../services/navidrome_client.dart';
import '../../widgets/pull_to_refresh.dart';
import '../../widgets/edge_back_gesture.dart';
import '../library/catalog_widgets.dart';
import '../library/cover_art.dart';

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key, required this.client, required this.onAlbum});
  final NavidromeClient client;
  final ValueChanged<Album> onAlbum;
  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  static const _categories = [
    ('Recently added', 'newest'),
    ('Most played', 'frequent'),
    ('Rediscover', 'random'),
    ('Favorite albums', 'starred'),
  ];
  final _art = <String, String?>{};
  List<String> _genres = [];
  List<Album> _albums = [];
  (String, String)? _selection;
  String? _genre;
  String? _error;
  bool _busy = false;
  bool _more = false;
  int _revision = 0;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (more && _busy) return;
    final revision = ++_revision;
    final selection = _selection;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (selection == null) {
        var failed = false;
        // Genre failure must not prevent the standard album categories working.
        final responses = await Future.wait([
          widget.client.genres().then<Object>((v) => v).catchError((Object _) {
            failed = true;
            return <String>[];
          }),
          for (final category in _categories)
            widget.client
                .discoverAlbums(type: category.$2, size: 1)
                .then<Object>((v) => v)
                .catchError((Object _) {
                  failed = true;
                  return <Album>[];
                }),
        ]);
        if (!mounted || revision != _revision) return;
        setState(() {
          if (failed) {
            _error =
                'Some discovery categories could not load. Please try again.';
          }
          _genres = responses[0] as List<String>;
          for (var i = 0; i < _categories.length; i++) {
            _art[_categories[i].$2] =
                (responses[i + 1] as List<Album>).firstOrNull?.coverArt;
          }
        });
      } else {
        final albums = await widget.client.discoverAlbums(
          type: selection.$2,
          genre: _genre,
          offset: more ? _albums.length : 0,
        );
        if (!mounted || revision != _revision) return;
        setState(() {
          _albums = more ? [..._albums, ...albums] : albums;
          // Random requests return a fresh selection, not stable pages.
          _more = selection.$2 != 'random' && albums.length == 40;
        });
      }
    } on NavidromeException catch (error) {
      if (mounted && revision == _revision) {
        setState(() => _error = error.message);
      }
    } finally {
      if (mounted && revision == _revision) setState(() => _busy = false);
    }
  }

  void _select((String, String)? category, {String? genre}) {
    setState(() {
      _selection = category;
      _genre = genre;
      _albums = [];
      _more = false;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _load();
  }

  Widget _tile(String title, String type, int index, {String? genre}) {
    final color = const [
      Color(0xff692b63),
      Color(0xff225569),
      Color(0xff735225),
      Color(0xff3c416f),
    ][index % 4];
    return Semantics(
      button: true,
      label: title,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Material(
          color: color,
          child: InkWell(
            onTap: () => _select((title, type), genre: genre),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (genre == null && _art[type] != null)
                  ExcludeSemantics(
                    child: CoverArt(
                      client: widget.client,
                      id: _art[type],
                      radius: 0,
                    ),
                  ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        color.withValues(alpha: .12),
                        Colors.black.withValues(alpha: .72),
                      ],
                    ),
                  ),
                ),
                if (genre != null)
                  Positioned(
                    right: -8,
                    top: -8,
                    child: Icon(
                      Icons.graphic_eq_rounded,
                      size: 112,
                      color: Colors.white.withValues(alpha: .12),
                    ),
                  ),
                Align(
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: ExcludeSemantics(
                      child: Text(
                        title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _grid(List<Widget> children) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
    sliver: SliverLayoutBuilder(
      builder: (context, constraints) => SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: (constraints.crossAxisExtent / 210).floor().clamp(
            2,
            4,
          ),
          mainAxisExtent: 150 + 36 * MediaQuery.textScalerOf(context).scale(1),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        delegate: SliverChildListDelegate(children),
      ),
    ),
  );

  Widget _heading(String text) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleLarge
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => EdgeBackGesture(
    onBack: _selection == null ? null : () => _select(null),
    child: PullToRefresh(
      onRefresh: _load,
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (_selection == null) ...[
            _heading('Browse your library'),
            _grid([
              for (var i = 0; i < _categories.length; i++)
                _tile(_categories[i].$1, _categories[i].$2, i),
            ]),
            if (_genres.isNotEmpty) ...[
              _heading('Genres'),
              _grid([
                for (var i = 0; i < _genres.length; i++)
                  _tile(_genres[i], 'byGenre', i, genre: _genres[i]),
              ]),
            ],
          ] else ...[
            SliverToBoxAdapter(
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _select(null),
                  icon: const Icon(Icons.chevron_left_rounded),
                  label: const Text('Back to discover'),
                ),
              ),
            ),
            _heading(_selection!.$1),
            AlbumGrid(
              albums: _albums,
              client: widget.client,
              onSelected: widget.onAlbum,
            ),
            if (!_busy && _error == null && _albums.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No albums here yet. Try another category.'),
                ),
              ),
            if (_more)
              SliverToBoxAdapter(
                child: TextButton(
                  onPressed: _busy ? null : () => _load(more: true),
                  child: const Text('More albums'),
                ),
              ),
          ],
          if (_busy) const SliverToBoxAdapter(child: LinearProgressIndicator()),
          if (_error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text(_error!),
                    TextButton(onPressed: _load, child: const Text('Retry')),
                  ],
                ),
              ),
            ),
          const SliverToBoxAdapter(child: DockSpacer()),
        ],
      ),
    ),
  );
}
