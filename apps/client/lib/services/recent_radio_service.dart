import '../models/recent_radio.dart';
import 'library_catalog.dart';

/// The fixed radio and editable playlists share this session's activity catalog.
class RecentRadioService extends LibraryCatalog {
  RecentRadioService(super.client, {super.now, super.cache});
  static const definition = RecentRadioDefinition();
  RadioPreview? _preview;
  int _previewRevision = -1;

  RadioPreview? get preview {
    if (revision == 0) return null;
    if (_previewRevision != revision) {
      _preview = RadioPreview.evaluate(tracks, definition, evaluatedAt);
      _previewRevision = revision;
    }
    return _preview;
  }
}
