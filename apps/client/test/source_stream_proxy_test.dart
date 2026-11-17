import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:hyperstream_client/models/source_reference.dart';
import 'package:hyperstream_client/services/mornye_provider.dart';
import 'package:hyperstream_client/services/mornye_sources.dart';
import 'package:hyperstream_client/services/source_stream_proxy.dart';

void main() {
  late MornyeSources sources;
  const track = SourceReference(
    sourceId: 'mornye:tidal-web',
    trackId: 'tidal:123',
  );
  setUp(() {
    sources = MornyeSources();
    sources.extensions = [
      MornyeExtension({
        'id': 'tidal-web',
        'display_name': 'Tidal',
        'version': '1.0.0',
        'download_url': 'https://example.test/package',
        'sha256': 'test',
        'audio': true,
        'installed': true,
        'enabled': true,
      }),
    ];
  });
  tearDown(() => sources.dispose());
  test('native queue URLs resolve lazily, preserve ranges, refresh expired links', () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <String?>[];
    upstream.listen((r) async {
      requests.add(r.headers.value('Range'));
      if (r.uri.path == '/expired') {
        r.response.statusCode = 403;
        await r.response.close();
        return;
      }
      r.response.statusCode = 206;
      r.response.headers.set('Content-Type', 'audio/flac');
      r.response.headers.set('Content-Range', 'bytes 2-4/6');
      r.response.contentLength = 3;
      r.response.add([2, 3, 4]);
      await r.response.close();
    });
    var resolves = 0;
    final proxy = SourceStreamProxy(
      sources,
      resolve: (_) async {
        resolves++;
        return SourceStreamMedia(
          uri: Uri.parse(
            'http://127.0.0.1:${upstream.port}/${resolves == 1 ? 'expired' : 'fresh'}',
          ),
        );
      },
    );
    await proxy.start();
    addTearDown(() async {
      await proxy.close();
      await upstream.close(force: true);
    });
    final url = proxy.uri(track);
    expect(resolves, 0);
    final response = await http.get(url, headers: {'Range': 'bytes=2-4'});
    expect(resolves, 2);
    expect(requests, ['bytes=2-4', 'bytes=2-4']);
    expect(response.statusCode, 206);
    expect(response.headers['content-range'], 'bytes 2-4/6');
    expect(response.bodyBytes, [2, 3, 4]);
    final forbidden = await http.get(url.replace(path: '/wrong-token/track'));
    expect(forbidden.statusCode, 404);
    expect(resolves, 2);
  });
  test('prepared files support seek ranges, HEAD and cleanup', () async {
    final directory = await Directory.systemTemp.createTemp(
      'hyperstream-proxy-',
    );
    final file = File('${directory.path}/source.flac');
    await file.writeAsBytes([0, 1, 2, 3, 4, 5]);
    final proxy = SourceStreamProxy(
      sources,
      resolve: (_) async =>
          SourceStreamMedia(file: PreparedSourceAudio(file, directory)),
    );
    await proxy.start();
    addTearDown(proxy.close);
    final url = proxy.uri(track);
    final response = await http.get(url, headers: {'Range': 'bytes=2-4'});
    expect(response.statusCode, 206);
    expect(response.bodyBytes, [2, 3, 4]);
    final head = await http.head(url);
    expect(head.headers['content-length'], '6');
    expect(head.bodyBytes, isEmpty);
    final invalid = await http.get(url, headers: {'Range': 'bytes=99-'});
    expect(invalid.statusCode, 416);
    expect(invalid.headers['content-range'], 'bytes */6');
    await proxy.close();
    expect(await directory.exists(), false);
  });
}
