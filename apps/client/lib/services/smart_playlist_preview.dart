import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/library.dart';
import '../models/smart_playlist.dart';
import 'library_catalog.dart';

typedef _Evaluation = (List<Track>, SmartPlaylistDefinition, DateTime);
SmartPlaylistResult _evaluate(_Evaluation args) =>
    SmartPlaylistResult.evaluate(args.$1, args.$2, args.$3);

/// Keeps a saved playlist current without modifying the player's queue.
class SmartPlaylistPreview extends ChangeNotifier {
  SmartPlaylistPreview(this.catalog) {
    catalog.addListener(_changed);
  }
  final LibraryCatalog catalog;
  SmartPlaylistDefinition? _definition;
  SmartPlaylistResult? result;
  bool busy = false;
  String? error;
  int _generation = 0;
  int _revision = -1;
  bool _disposed = false;

  void _changed() {
    if (catalog.revision != _revision && _definition != null) {
      unawaited(update(_definition!));
    }
  }

  Future<void> update(SmartPlaylistDefinition definition) async {
    if (_disposed) return;
    _definition = definition;
    _revision = catalog.revision;
    final generation = ++_generation;
    error = null;
    if (catalog.lastSyncedAt == null) {
      result = null;
      busy = false;
      notifyListeners();
      return;
    }
    busy = true;
    notifyListeners();
    try {
      final args = (catalog.tracks, definition, catalog.currentTime);
      final next = catalog.tracks.length > 5000
          ? await compute(_evaluate, args)
          : _evaluate(args);
      if (!_disposed && generation == _generation) result = next;
    } on FormatException catch (failure) {
      if (!_disposed && generation == _generation) {
        result = null;
        error = failure.message;
      }
    } on Object {
      if (!_disposed && generation == _generation) {
        result = null;
        error = 'The playlist preview could not be calculated.';
      }
    } finally {
      if (!_disposed && generation == _generation) {
        busy = false;
        notifyListeners();
      }
    }
  }

  void clear() {
    _definition = null;
    _generation++;
    result = null;
    busy = false;
    error = null;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    catalog.removeListener(_changed);
    super.dispose();
  }
}
