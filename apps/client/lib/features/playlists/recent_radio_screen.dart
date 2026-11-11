import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/recent_radio.dart';
import '../../services/playback_service.dart';
import '../../services/recent_radio_service.dart';
import '../../widgets/pull_to_refresh.dart';
import '../library/cover_art.dart';

class RecentRadioScreen extends StatefulWidget {
  const RecentRadioScreen({
    super.key,
    required this.radio,
    required this.playback,
    required this.active,
  });
  final RecentRadioService radio;
  final PlaybackService playback;
  final bool active;
  @override
  State<RecentRadioScreen> createState() => _RecentRadioScreenState();
}

class _RecentRadioScreenState extends State<RecentRadioScreen>
    with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _days = TextEditingController();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_open());
  }

  Future<void> _open() async {
    await widget.radio.initialize();
    if (!mounted) return;
    _name.text = widget.radio.definition.name;
    _days.text = '${widget.radio.definition.days}';
    setState(() => _ready = true);
    await widget.radio.refresh();
  }

  @override
  void didUpdateWidget(covariant RecentRadioScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) unawaited(widget.radio.refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.active) {
      unawaited(widget.radio.refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _name.dispose();
    _days.dispose();
    super.dispose();
  }

  void _preview() {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    unawaited(
      widget.radio.configure(
        RecentRadioDefinition(
          name: _name.text.trim(),
          days: int.parse(_days.text.trim()),
        ),
      ),
    );
  }

  String _updated(DateTime time) {
    final local = time.toLocal();
    final labels = MaterialLocalizations.of(context);
    return '${labels.formatShortDate(local)} ${labels.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }

  void _play(RadioPreview preview, [int index = 0]) => unawaited(
    widget.playback.playAlbum(
      widget.radio.client,
      preview.matches.map((match) => match.track).toList(),
      index,
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.radio,
    builder: (context, _) {
      final radio = widget.radio;
      final preview = radio.preview;
      return PullToRefresh(
        onRefresh: radio.refresh,
        child: CustomScrollView(
          key: const PageStorageKey('recent-radio'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recent Radio',
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Recently added and recently played, ordered by your latest activity.',
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _name,
                        enabled: _ready,
                        maxLength: 120,
                        decoration: const InputDecoration(
                          labelText: 'Radio name',
                          counterText: '',
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Enter a name.'
                            : value.trim().length > 120
                            ? 'Use a shorter name.'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _days,
                        enabled: _ready,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Added or played within',
                          suffixText: 'days',
                        ),
                        validator: (value) {
                          final days = int.tryParse(value?.trim() ?? '');
                          return days == null || days < 1 || days > 3650
                              ? 'Choose 1 to 3650 days.'
                              : null;
                        },
                        onFieldSubmitted: (_) {
                          if (!radio.loading) _preview();
                        },
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: radio.loading || !_ready
                                ? null
                                : _preview,
                            icon: const Icon(Icons.tune_rounded),
                            label: const Text('Update preview'),
                          ),
                          FilledButton.icon(
                            onPressed:
                                preview == null || preview.matches.isEmpty
                                ? null
                                : () => _play(preview),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('Play radio'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Refreshes when you open this radio or return to the app. Pull down to refresh. Your playing queue stays as it is.',
                      ),
                      if (!widget.playback.preferences.reportListens)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text(
                            'Listening reports are off on this device. Enable them in Home > Playback to count your Hyperstream listens.',
                          ),
                        ),
                      if (radio.storageNotice case final String notice)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(notice),
                        ),
                      if (radio.loading || !_ready) ...[
                        const SizedBox(height: 16),
                        const LinearProgressIndicator(),
                        Text(
                          _ready
                              ? 'Reading library · ${radio.loadedCount} songs'
                              : 'Loading radio settings…',
                        ),
                      ],
                      if (radio.error case final String error) ...[
                        const SizedBox(height: 16),
                        Text(
                          error,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        if (preview != null)
                          const Text('Showing the last successful preview.'),
                        TextButton(
                          onPressed: radio.loading ? null : radio.refresh,
                          child: const Text('Retry'),
                        ),
                      ],
                      if (preview != null) ...[
                        const SizedBox(height: 24),
                        Text(
                          preview.definition.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          '${preview.matches.length} matches · ${preview.definition.days} days · ${preview.libraryCount} library songs',
                        ),
                        Text('Updated ${_updated(preview.evaluatedAt)}'),
                        if (!preview.hasPlayDates && preview.libraryCount > 0)
                          const Text(
                            'No usable play dates are available yet. Only addition dates can contribute to this preview.',
                          ),
                        if (preview.missingDates > 0)
                          Text(
                            '${preview.missingDates} songs have no usable activity dates and were omitted.',
                          ),
                        if (preview.invalidDates > 0)
                          Text(
                            '${preview.invalidDates} songs contain invalid or future dates. Those dates were ignored.',
                          ),
                        if (radio.activityChanged)
                          const Text(
                            'New listening activity is available. Pull down to refresh.',
                          ),
                        if (preview.matches.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 16),
                            child: Text(
                              'No songs match this window. Try more days or listen to a song.',
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (preview != null)
              SliverList.builder(
                itemCount: preview.matches.length,
                itemBuilder: (context, index) {
                  final match = preview.matches[index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 4,
                    ),
                    leading: SizedBox(
                      width: 48,
                      height: 48,
                      child: CoverArt(
                        client: radio.client,
                        id: match.track.coverArt,
                      ),
                    ),
                    title: Text(
                      match.track.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${match.track.artist}\n${match.reason}',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _play(preview, index),
                  );
                },
              ),
            const SliverToBoxAdapter(child: DockSpacer()),
          ],
        ),
      );
    },
  );
}
