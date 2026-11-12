import '../../widgets/glass_overlays.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../widgets/floating_chrome.dart';
import '../../widgets/edge_back_gesture.dart';
import '../../models/smart_playlist.dart';
import '../../services/library_catalog.dart';
import '../../services/playback_service.dart';
import '../../services/smart_playlist_preview.dart';
import '../../services/smart_playlist_store.dart';
import 'smart_rule_editor.dart';
import 'smart_playlist_results.dart';

class SmartPlaylistEditor extends StatefulWidget {
  const SmartPlaylistEditor({
    super.key,
    required this.initial,
    required this.catalog,
    required this.store,
    required this.playback,
  });
  final SmartPlaylistDefinition initial;
  final LibraryCatalog catalog;
  final SmartPlaylistStore store;
  final PlaybackService playback;
  @override
  State<SmartPlaylistEditor> createState() => _SmartPlaylistEditorState();
}

class _SmartPlaylistEditorState extends State<SmartPlaylistEditor> {
  late final _name = TextEditingController(text: widget.initial.name);
  late final _limit = TextEditingController(
    text: widget.initial.limit?.toString() ?? '',
  );
  late SmartPlaylistType _type = widget.initial.type;
  late SmartGroup _include = widget.initial.include;
  late SmartGroup _exclude = widget.initial.exclude;
  late final List<SmartPool> _pools = [...widget.initial.pools];
  late SmartOrder _order = widget.initial.order;
  late bool _fill = widget.initial.fillWhenEmpty;
  late final _preview = SmartPlaylistPreview(widget.catalog);
  bool _dirty = false;
  bool _saving = false;
  bool _allowPop = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.catalog.ensureLoaded());
    });
  }

  @override
  void dispose() {
    _preview.dispose();
    _name.dispose();
    _limit.dispose();
    super.dispose();
  }

  void _change(VoidCallback action) {
    _preview.clear();
    setState(() {
      action();
      _dirty = true;
      _error = null;
    });
  }

  SmartPlaylistDefinition _definition() {
    final limitText = _limit.text.trim();
    final limit = limitText.isEmpty ? null : int.tryParse(limitText);
    if (limitText.isNotEmpty && limit == null) {
      throw const FormatException('Enter a whole-number track limit.');
    }
    final definition = SmartPlaylistDefinition(
      id: widget.initial.id,
      name: _name.text.trim(),
      type: _type,
      include: _include,
      exclude: _exclude,
      pools: _pools,
      order: _order,
      limit: limit,
      fillWhenEmpty: _fill,
    );
    definition.validate();
    return definition;
  }

  void _showPreview() {
    try {
      final definition = _definition();
      setState(() => _error = null);
      unawaited(_preview.update(definition));
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  Future<void> _save() async {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    SmartPlaylistDefinition definition;
    try {
      definition = _definition();
    } on FormatException catch (error) {
      _saveError(error.message);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final saved = await widget.store.save(definition);
    if (!mounted) return;
    if (!saved) {
      setState(() {
        _saving = false;
      });
      _saveError(widget.store.error ?? 'Could not save this playlist.');
      return;
    }
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context, definition.id);
  }

  void _saveError(String message) {
    setState(() => _error = message);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _close() async {
    if (_saving || _allowPop) return;
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => GlassAlertDialog(
          title: const Text('Discard changes?'),
          content: const Text('Your unsaved playlist settings will be lost.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context);
  }

  Future<void> _editPool([int? index]) async {
    final pool = await Navigator.push<SmartPool>(
      context,
      MenuPageRoute(
        builder: (_) => _PoolPage(
          initial: index == null
              ? SmartPool(
                  name: 'Pool ${_pools.length + 1}',
                  rules: SmartGroup(),
                  share: 0,
                )
              : _pools[index],
        ),
      ),
    );
    if (pool == null || !mounted) return;
    _change(() {
      if (index == null) {
        _pools.add(pool);
      } else {
        _pools[index] = pool;
      }
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPop || (!_dirty && !_saving),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_close());
    },
    child: Scaffold(
      appBar: FloatingAppBar(
        title: 'Smart playlist',
        actions: [
          TextButton(
            onPressed: _saving || !widget.store.canWrite ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save'),
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _saving,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 850),
            child: ListenableBuilder(
              listenable: Listenable.merge([widget.catalog, _preview]),
              builder: (context, _) => ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  TextField(
                    controller: _name,
                    maxLength: 120,
                    decoration: const InputDecoration(
                      labelText: 'Playlist name',
                      counterText: '',
                    ),
                    onChanged: (_) => _change(() {}),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Playlist type',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<SmartPlaylistType>(
                    segments: const [
                      ButtonSegment(
                        value: SmartPlaylistType.rules,
                        label: Text('Rules'),
                        icon: Icon(Icons.filter_alt_outlined),
                      ),
                      ButtonSegment(
                        value: SmartPlaylistType.mix,
                        label: Text('Mix'),
                        icon: Icon(Icons.shuffle_rounded),
                      ),
                    ],
                    selected: {_type},
                    onSelectionChanged: (value) =>
                        _change(() => _type = value.single),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _type == SmartPlaylistType.rules
                        ? 'Filter one list, then choose its order.'
                        : 'Give each pool its own rules and order, then mix by share.',
                  ),
                  const SizedBox(height: 16),
                  if (_type == SmartPlaylistType.rules) ...[
                    SmartRuleEditor(
                      title: 'Include',
                      group: _include,
                      onChanged: (value) => _change(() => _include = value),
                    ),
                    const SizedBox(height: 12),
                    SmartOrderPicker(
                      order: _order,
                      onChanged: (value) => _change(() => _order = value),
                    ),
                    if (_order == SmartOrder.activity)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Uses whichever happened later: added or played.',
                        ),
                      ),
                  ] else ...[
                    for (final (index, pool) in _pools.indexed)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text('${pool.name} · ${pool.share}%'),
                                subtitle: Text(
                                  '${pool.rules.summary}\n${pool.order.label}',
                                ),
                                trailing: const Icon(Icons.edit_outlined),
                                onTap: () => _editPool(index),
                              ),
                              Wrap(
                                children: [
                                  IconButton(
                                    tooltip: 'Move pool up',
                                    onPressed: index == 0
                                        ? null
                                        : () => _change(() {
                                            final previous = _pools[index - 1];
                                            _pools[index - 1] = pool;
                                            _pools[index] = previous;
                                          }),
                                    icon: const Icon(
                                      Icons.arrow_upward_rounded,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Move pool down',
                                    onPressed: index == _pools.length - 1
                                        ? null
                                        : () => _change(() {
                                            final next = _pools[index + 1];
                                            _pools[index + 1] = pool;
                                            _pools[index] = next;
                                          }),
                                    icon: const Icon(
                                      Icons.arrow_downward_rounded,
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: _pools.length == 1
                                        ? null
                                        : () => _change(
                                            () => _pools.removeAt(index),
                                          ),
                                    icon: const Icon(Icons.close_rounded),
                                    label: const Text('Remove pool'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    TextButton.icon(
                      onPressed: _pools.length >= 8 ? null : () => _editPool(),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add pool'),
                    ),
                    Text(
                      'Total share: ${_pools.fold(0, (sum, pool) => sum + pool.share)}% · must equal 100%',
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Fill from remaining pools'),
                      subtitle: const Text(
                        'When off, stop when any enabled pool runs out.',
                      ),
                      value: _fill,
                      onChanged: (value) => _change(() => _fill = value),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SmartRuleEditor(
                    title: 'Exclude',
                    group: _exclude,
                    onChanged: (value) => _change(() => _exclude = value),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _limit,
                    maxLength: 5,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Track limit',
                      hintText: 'All matching tracks',
                      counterText: '',
                    ),
                    onChanged: (_) => _change(() {}),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Duplicate tracks appear once. Settings are saved on this device for the current account.',
                  ),
                  const SizedBox(height: 20),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  FilledButton.tonalIcon(
                    onPressed: _preview.busy ? null : _showPreview,
                    icon: const Icon(Icons.preview_outlined),
                    label: const Text('Preview tracks'),
                  ),
                  const SizedBox(height: 16),
                  SmartPlaylistResults(
                    catalog: widget.catalog,
                    preview: _preview,
                    playback: widget.playback,
                    definition: _preview.result == null
                        ? null
                        : _previewDefinition(),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  SmartPlaylistDefinition? _previewDefinition() {
    try {
      return _definition();
    } on FormatException {
      return null;
    }
  }
}

class SmartOrderPicker extends StatelessWidget {
  const SmartOrderPicker({
    super.key,
    required this.order,
    required this.onChanged,
  });
  final SmartOrder order;
  final ValueChanged<SmartOrder> onChanged;
  @override
  Widget build(BuildContext context) => GlassDropdownField<SmartOrder>(
    initialValue: order,
    isExpanded: true,
    decoration: const InputDecoration(labelText: 'Order'),
    items: SmartOrder.values
        .map(
          (order) => DropdownMenuItem(value: order, child: Text(order.label)),
        )
        .toList(),
    onChanged: (value) => onChanged(value!),
  );
}

class _PoolPage extends StatefulWidget {
  const _PoolPage({required this.initial});
  final SmartPool initial;
  @override
  State<_PoolPage> createState() => _PoolPageState();
}

class _PoolPageState extends State<_PoolPage> {
  late final _name = TextEditingController(text: widget.initial.name);
  late final _share = TextEditingController(text: '${widget.initial.share}');
  late SmartGroup _rules = widget.initial.rules;
  late SmartOrder _order = widget.initial.order;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _share.dispose();
    super.dispose();
  }

  void _done() {
    final share = int.tryParse(_share.text);
    if (_name.text.trim().isEmpty ||
        _name.text.trim().length > 80 ||
        share == null ||
        share < 0 ||
        share > 100) {
      setState(
        () => _error =
            'Enter a pool name and a whole-number share from 0 to 100.',
      );
      return;
    }
    Navigator.pop(
      context,
      SmartPool(
        name: _name.text.trim(),
        rules: _rules,
        share: share,
        order: _order,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: FloatingAppBar(
      title: 'Mix pool',
      actions: [TextButton(onPressed: _done, child: const Text('Done'))],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 750),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: _name,
              maxLength: 80,
              decoration: const InputDecoration(labelText: 'Pool name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _share,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Share',
                suffixText: '%',
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'A 0% share disables this pool. Changes apply when you choose Done.',
            ),
            const SizedBox(height: 16),
            SmartRuleEditor(
              title: 'Pool conditions',
              group: _rules,
              onChanged: (value) => setState(() => _rules = value),
            ),
            const SizedBox(height: 16),
            SmartOrderPicker(
              order: _order,
              onChanged: (value) => setState(() => _order = value),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
  );
}
