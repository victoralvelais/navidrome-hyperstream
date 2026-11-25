import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:hyperstream_client/models/library.dart';
import 'package:hyperstream_client/models/source_reference.dart';
import 'package:hyperstream_client/services/mornye_sources.dart';
import 'package:hyperstream_client/services/music_provider.dart';
import 'package:hyperstream_client/services/music_sources.dart';
import 'package:hyperstream_client/services/online_search.dart';

Track song(
  String provider,
  String id,
  String title, {
  String artist = 'Artist',
}) => Track(
  id: 'external:$provider:$id',
  title: title,
  artist: artist,
  album: '',
  duration: const Duration(minutes: 3),
  source: SourceReference(sourceId: provider, trackId: id),
);
SourceSearch found(List<Track> tracks) =>
    SourceSearch(tracks: tracks, albums: const []);

void main() {
  test('publishes fast results, ranks across sources, keeps versions and stable ties', () async {
    final slow = Completer<SourceSearch>();
    final spotify = FakeProvider('mornye:spotify-web', (_, _) => slow.future);
    final sc = FakeProvider(
      'mornye:soundcloud',
      (_, _) async => found([
        song('mornye:soundcloud', 'other', 'Unrelated'),
        song('mornye:soundcloud', 'remix', 'Night Drive Remix'),
        song('mornye:soundcloud', 'remix', 'Night Drive Remix'),
      ]),
    );
    final sources = FakeSources([spotify, sc]);
    final search = OnlineSearch(sources, 'night drive');
    addTearDown(() {
      search.dispose();
      sources.dispose();
    });
    final done = search.start();
    await Future<void>.delayed(Duration.zero);
    expect(search.busy, true);
    expect(search.tracks.map((t) => t.title), [
      'Night Drive Remix',
      'Unrelated',
    ]);
    slow.complete(
      found([
        song(spotify.id, 'studio', 'Night Drive'),
        song(spotify.id, 'remix', 'Night Drive Remix'),
      ]),
    );
    await done;
    expect(search.tracks.first.title, 'Night Drive');
    expect(
      search.tracks.where((t) => t.title == 'Night Drive Remix'),
      hasLength(2),
    );
    expect(
      search.tracks.map((t) => t.source!.sourceId),
      containsAll([spotify.id, sc.id]),
    );
    expect(search.busy, false);
    expect([spotify.closed, sc.closed], [true, true]);
  });

  test(
    'ranks artist/title matches and requested remix over unrelated top results',
    () {
      final score = OnlineSearch.relevance;
      expect(
        score('artist night drive', 'Night Drive', 'Artist', 20),
        greaterThan(score('artist night drive', 'Unrelated', 'Artist', 0)),
      );
      expect(
        score('night drive remix', 'Night Drive Remix', 'DJ', 20),
        greaterThan(score('night drive remix', 'Night Drive', 'Artist', 0)),
      );
      expect(
        score('東京 夜', '東京・夜', 'Artist', 1),
        greaterThan(score('東京 夜', 'Other', 'Artist', 0)),
      );
      expect(
        score('night-drive', 'NIGHT DRIVE', 'Artist', 0),
        score('night drive', 'Night Drive', 'Artist', 0),
      );
    },
  );

  test(
    'one failure does not erase another source; retry targets only the failure',
    () async {
      var fail = true;
      final good = FakeProvider(
        'mornye:soundcloud',
        (_, _) async => found([song('mornye:soundcloud', '1', 'Music')]),
      );
      final bad = FakeProvider('mornye:tidal-web', (_, _) async {
        if (fail) throw const SourceException('private provider details');
        return found([song('mornye:tidal-web', '2', 'Music')]);
      });
      final sources = FakeSources([good, bad]);
      final search = OnlineSearch(sources, 'music');
      addTearDown(() {
        search.dispose();
        sources.dispose();
      });
      await search.start();
      expect(search.tracks, hasLength(1));
      expect(search.issues.single.source.id, bad.id);
      fail = false;
      await search.retry(search.issues.single);
      expect(search.tracks, hasLength(2));
      expect(search.issues, isEmpty);
      expect([good.calls, bad.calls], [1, 2]);
    },
  );

  test('pasted links query only their enabled matching provider', () async {
    final sc = FakeProvider('mornye:soundcloud', (_, _) async => found([]));
    final youtube = FakeProvider(
      'mornye:ytmusic-spotiflac',
      (_, _) async => found([]),
    );
    final sources = FakeSources([sc, youtube]);
    final search = OnlineSearch(sources, 'https://soundcloud.com/dj/remix');
    await search.start();
    expect([sc.calls, youtube.calls], [1, 0]);
    search.dispose();
    final unknown = OnlineSearch(
      sources,
      'https://soundcloud.com.evil.test/dj/remix',
    );
    await unknown.start();
    expect(unknown.error, contains('matching music source'));
    expect([sc.calls, youtube.calls], [1, 0]);
    unknown.dispose();
    sources.dispose();
  });

  test('timeouts cancel slow requests and ignore late results', () async {
    final slow = Completer<SourceSearch>();
    final cancelled = Completer<void>();
    final bad = FakeProvider('mornye:tidal-web', (_, abort) {
      abort!.then((_) => cancelled.complete());
      return slow.future;
    });
    final good = FakeProvider(
      'mornye:soundcloud',
      (_, _) async => found([song('mornye:soundcloud', '1', 'Music')]),
    );
    final sources = FakeSources([bad, good]);
    final search = OnlineSearch(
      sources,
      'music',
      timeout: const Duration(milliseconds: 20),
    );
    await search.start();
    expect(bad.calls, 1);
    await cancelled.future.timeout(const Duration(seconds: 1));
    expect(search.tracks, hasLength(1));
    expect(search.issues.single.source.id, bad.id);
    slow.complete(found([song(bad.id, 'late', 'Music')]));
    await Future<void>.delayed(Duration.zero);
    expect(search.tracks, hasLength(1));
    search.dispose();
    sources.dispose();
  });

  test(
    'disposal cancels active searches and prevents queued sources starting',
    () async {
      final waits = List.generate(5, (_) => Completer<SourceSearch>());
      var cancellations = 0;
      final providers = List.generate(
        5,
        (i) => FakeProvider('mornye:$i', (_, abort) {
          abort!.then((_) {
            cancellations++;
            waits[i].complete(found([]));
          });
          return waits[i].future;
        }),
      );
      final sources = FakeSources(providers);
      final search = OnlineSearch(sources, 'music');
      final done = search.start();
      expect(providers.map((p) => p.calls), [1, 1, 1, 0, 0]);
      search.dispose();
      await done;
      expect(cancellations, 3);
      expect(providers.map((p) => p.calls), [1, 1, 1, 0, 0]);
      sources.dispose();
    },
  );

  test('aggregate verification stays inline until requested and retries one provider', () async {
    var verified = false, prompts = 0;
    final extensions = MornyeSources();
    extensions.presentVerification = (id) async {
      expect(id, 'qobuz-web');
      prompts++;
      verified = true;
      return true;
    };
    final qobuz = FakeProvider('mornye:qobuz-web', (_, _) async {
      if (!verified) throw ProviderVerificationRequired('qobuz-web');
      return found([song('mornye:qobuz-web', '1', 'Music')]);
    });
    final sources = FakeSources([qobuz], extensions: extensions);
    final search = OnlineSearch(sources, 'music');
    await search.start();
    expect(prompts, 0);
    expect(search.issues.single.verificationProvider, 'qobuz-web');
    await search.retry(search.issues.single);
    expect(prompts, 1);
    expect(search.tracks, hasLength(1));
    expect(search.issues, isEmpty);
    search.dispose();
    sources.dispose();
    extensions.dispose();
  });
}

class FakeSources extends MusicSources {
  FakeSources(this.providers, {super.extensions});
  final List<FakeProvider> providers;
  @override
  List<OnlineSource> get onlineSources =>
      providers.map((p) => OnlineSource(p.id, p.name)).toList();
  @override
  MusicProvider providerById([String? requested]) =>
      providers.firstWhere((p) => p.id == requested);
}

class FakeProvider implements MusicProvider {
  FakeProvider(this.id, this.onSearch);
  @override
  final String id;
  final Future<SourceSearch> Function(String, Future<void>?) onSearch;
  int calls = 0;
  bool closed = false;
  @override
  String get name => id;
  @override
  Future<SourceSearch> search(String query, {Future<void>? abort}) {
    calls++;
    return onSearch(query, abort);
  }

  @override
  Future<List<Track>> album(SourceAlbum album) async => [];
  @override
  Uri streamUri(SourceReference track) =>
      Uri.parse('https://example.test/audio');
  @override
  Future<http.StreamedResponse> download(
    SourceReference track,
    Future<void> abort,
  ) async => throw UnimplementedError();
  @override
  void close() => closed = true;
}
