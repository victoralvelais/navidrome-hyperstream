import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';

import '../../services/music_sources.dart';
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
      final enabled = sources.extensions?.enabled.toList() ?? [];
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
          for (final source in enabled)
            PopupMenuItem(
              key: ValueKey('online-source-${source.id}'),
              value: source.id,
              child: _sourceRow(
                source.name,
                source.id == sources.selectedProvider,
              ),
            ),
          if (sources.enabled)
            PopupMenuItem(
              key: const ValueKey('online-source-monochrome'),
              value: sources.sourceId,
              child: _sourceRow(
                'Monochrome',
                sources.sourceId == sources.selectedProvider,
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
      } else if (sources.extensions != null) {
        await sources.extensions!.choose(
          catalog: selected,
          legacy: selected == sources.sourceId,
        );
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

  Widget _sourceRow(String name, bool selected) => Row(
    children: [
      Expanded(child: Text(name)),
      const SizedBox(width: 12),
      if (selected)
        Icon(
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
      final selected = widget.sources.selectedProvider;
      final source = selected == widget.sources.sourceId
          ? 'Monochrome'
          : selected == null
          ? 'No source selected'
          : widget.sources.extensions?.name(selected) ?? '';
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
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                constraints: const BoxConstraints(minHeight: 44),
                margin: const EdgeInsets.all(3),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: widget.enabled
                      ? LinearGradient(
                          colors: [
                            colors.primary.withValues(alpha: .18),
                            colors.primary.withValues(alpha: .04),
                          ],
                        )
                      : null,
                  color: _focused || _hovered
                      ? colors.onSurface.withValues(alpha: .06)
                      : null,
                ),
                child: ExcludeSemantics(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
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
                          fontWeight: widget.enabled
                              ? FontWeight.w700
                              : FontWeight.w500,
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
