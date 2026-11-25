import 'package:hyperstream_client/widgets/app_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';

import '../../services/music_sources.dart';
import '../../widgets/music_source_icon.dart';
import '../settings/music_source_settings.dart';

/// A status indicator that also toggles online results. Source selection stays
/// behind a long press, secondary click, or the accessible context-menu action.
class OnlineSearchToggle extends StatefulWidget {
  const OnlineSearchToggle({
    super.key,
    required this.enabled,
    required this.onChanged,
    required this.sources,
  });
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final MusicSources sources;

  @override
  State<OnlineSearchToggle> createState() => _OnlineSearchToggleState();
}

class _OnlineSearchToggleState extends State<OnlineSearchToggle> {
  final _anchor = GlobalKey();
  static const _manage = '__manage_sources';
  static const _all = '__all_sources';
  static const _sourceAction = CustomSemanticsAction(
    label: 'Choose music source',
  );
  bool _menuOpen = false;
  bool _focused = false;
  bool _hovered = false;

  void _toggle() => widget.onChanged(!widget.enabled);

  Future<void> _chooseSource() async {
    if (_menuOpen) return;
    _menuOpen = true;
    try {
      final sources = widget.sources;
      final enabled = sources.onlineSources;
      final colors = Theme.of(context).colorScheme;
      final selected = await showMenu<String>(
        context: context,
        positionBuilder: (context, constraints) {
          final overlay =
              Navigator.of(context).overlay!.context.findRenderObject()!
                  as RenderBox;
          final anchor =
              _anchor.currentContext?.findRenderObject() as RenderBox?;
          final origin =
              anchor?.localToGlobal(Offset.zero, ancestor: overlay) ??
              Offset.zero;
          final size = anchor?.size ?? Size.zero;
          return RelativeRect.fromRect(
            Rect.fromLTWH(
              origin.dx,
              origin.dy + size.height + 6,
              size.width,
              0,
            ),
            Offset.zero & overlay.size,
          );
        },
        color: colors.surfaceContainerHigh.withValues(alpha: .97),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: colors.onSurface.withValues(alpha: .12)),
        ),
        elevation: 12,
        items: [
          PopupMenuItem(
            key: const ValueKey('online-source-all'),
            value: _all,
            child: _sourceRow('All sources', sources.searchSource == null),
          ),
          for (final source in enabled)
            PopupMenuItem(
              key: ValueKey(
                'online-source-${source.id.startsWith('mornye:') ? source.id.substring(7) : 'monochrome'}',
              ),
              value: source.id,
              child: _sourceRow(
                source.name,
                source.id == sources.searchSource,
                sourceId: source.id,
              ),
            ),
          if (sources.hasProviders) const PopupMenuDivider(),
          const PopupMenuItem(value: _manage, child: Text('Music sources…')),
        ],
      );
      if (!mounted || selected == null) return;
      if (selected == _manage) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('Music sources')),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: MusicSourceSettings(sources: sources),
              ),
            ),
          ),
        );
      } else {
        await sources.chooseSearchSource(selected == _all ? null : selected);
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not change the music source. Try again.'),
          ),
        );
      }
    } finally {
      _menuOpen = false;
    }
  }

  Widget _sourceRow(String name, bool selected, {String? sourceId}) => Row(
    children: [
      if (sourceId != null) ...[
        MusicSourceIcon(sourceId: sourceId, name: name),
        const SizedBox(width: 10),
      ],
      Expanded(child: Text(name)),
      const SizedBox(width: 12),
      if (selected)
        AppIcon(
          Icons.check_rounded,
          size: 20,
          color: Theme.of(context).colorScheme.primary,
        ),
    ],
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.sources,
    builder: (context, _) {
      final colors = Theme.of(context).colorScheme;
      final source = widget.sources.searchLabel;
      return Semantics(
        label: 'Online results',
        value: source,
        toggled: widget.enabled,
        hint: widget.enabled
            ? 'Tap to hide online results. Hold to choose a music source.'
            : 'Tap to include online results. Hold to choose a music source.',
        onTap: _toggle,
        onLongPress: _chooseSource,
        customSemanticsActions: {_sourceAction: _chooseSource},
        child: FocusableActionDetector(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.f10, shift: true):
                _ChooseSourceIntent(),
          },
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                _toggle();
                return null;
              },
            ),
            _ChooseSourceIntent: CallbackAction<_ChooseSourceIntent>(
              onInvoke: (_) {
                _chooseSource();
                return null;
              },
            ),
          },
          onShowFocusHighlight: (value) => setState(() => _focused = value),
          onShowHoverHighlight: (value) => setState(() => _hovered = value),
          mouseCursor: SystemMouseCursors.click,
          child: Tooltip(
            message:
                'Online results · $source\nHold or right-click to choose a source',
            triggerMode: TooltipTriggerMode.manual,
            excludeFromSemantics: true,
            child: GestureDetector(
              key: _anchor,
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTap: _toggle,
              onLongPress: _chooseSource,
              onSecondaryTap: _chooseSource,
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: ExcludeSemantics(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppIcon(
                        Icons.public_rounded,
                        size: 19,
                        color: widget.enabled
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Online',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: widget.enabled
                              ? colors.primary
                              : colors.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          decoration: _focused || _hovered
                              ? TextDecoration.underline
                              : TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _ChooseSourceIntent extends Intent {
  const _ChooseSourceIntent();
}
