import 'package:flutter/material.dart';

import 'glass_surface.dart';
import 'pull_down_sheet.dart';

Widget _inheritGlass(BuildContext source, Widget child) => _OverlayGlass(
  enabled: GlassScope.effectsEnabled(source),
  color: ArtworkTint.of(source),
  child: child,
);

class _OverlayGlass extends StatelessWidget {
  const _OverlayGlass({
    required this.enabled,
    required this.color,
    required this.child,
  });
  final bool enabled;
  final Color? color;
  final Widget child;
  @override
  Widget build(BuildContext context) => GlassScope(
    enabled: context.getInheritedWidgetOfExactType<GlassScope>() == null
        ? enabled
        : GlassScope.effectsEnabled(context),
    child: ArtworkTint(color: color, child: child),
  );
}

Future<T?> showGlassSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool useSafeArea = true,
  bool pullFromList = false,
  BoxConstraints? constraints,
}) {
  final enabled = GlassScope.effectsEnabled(context);
  final tint = ArtworkTint.of(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    backgroundColor: Colors.transparent,
    elevation: 0,
    showDragHandle: false,
    constraints: constraints ?? const BoxConstraints(maxWidth: 640),
    builder: (context) => _OverlayGlass(
      enabled: enabled,
      color: tint,
      child: Builder(
        builder: (context) {
          final surface = Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: GlassSurface(
              radius: 32,
              prominent: true,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Builder(builder: builder),
                ),
              ),
            ),
          );
          return pullFromList ? PullDownSheet(child: surface) : surface;
        },
      ),
    ),
  );
}

/// Retains Flutter's menu navigation, focus handling, and dismissal semantics.
/// One shared glass surface covers the entire menu rather than frosting rows.
class GlassPopupMenuButton<T> extends StatelessWidget {
  const GlassPopupMenuButton({
    super.key,
    required this.itemBuilder,
    this.onSelected,
    this.icon,
    this.tooltip,
    this.enabled = true,
    this.child,
  });
  final PopupMenuItemBuilder<T> itemBuilder;
  final PopupMenuItemSelected<T>? onSelected;
  final Widget? icon;
  final Widget? child;
  final String? tooltip;
  final bool enabled;

  @override
  Widget build(BuildContext context) => PopupMenuButton<T>(
    tooltip: tooltip,
    enabled: enabled,
    icon: icon,
    onSelected: onSelected,
    elevation: 0,
    color: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    shadowColor: Colors.transparent,
    menuPadding: EdgeInsets.zero,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    constraints: const BoxConstraints(minWidth: 224, maxWidth: 340),
    itemBuilder: (_) => [
      _GlassMenuEntry<T>(
        child: _inheritGlass(
          context,
          GlassSurface(
            radius: 28,
            prominent: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: itemBuilder(context),
              ),
            ),
          ),
        ),
      ),
    ],
    child: child,
  );
}

class _GlassMenuEntry<T> extends PopupMenuEntry<T> {
  const _GlassMenuEntry({required this.child});
  final Widget child;
  @override
  double get height => 0;
  @override
  bool represents(T? value) => false;
  @override
  State<_GlassMenuEntry<T>> createState() => _GlassMenuEntryState<T>();
}

class _GlassMenuEntryState<T> extends State<_GlassMenuEntry<T>> {
  @override
  Widget build(BuildContext context) => widget.child;
}

class GlassDropdownField<T> extends StatelessWidget {
  const GlassDropdownField({
    super.key,
    required this.items,
    required this.onChanged,
    this.initialValue,
    this.decoration = const InputDecoration(),
    this.isExpanded = true,
  });
  final T? initialValue;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final InputDecoration decoration;
  final bool isExpanded;

  @override
  Widget build(BuildContext context) => GlassPopupMenuButton<T>(
    tooltip: decoration.labelText ?? 'Choose',
    enabled: onChanged != null,
    onSelected: onChanged,
    itemBuilder: (_) => [
      for (final item in items)
        PopupMenuItem<T>(
          value: item.value,
          enabled: item.enabled,
          child: Row(
            children: [
              Expanded(child: item.child),
              if (item.value == initialValue)
                const Icon(Icons.check_rounded, size: 18),
            ],
          ),
        ),
    ],
    child: InputDecorator(
      decoration: decoration.copyWith(enabled: onChanged != null),
      child: Row(
        children: [
          Expanded(
            child:
                items
                    .where((i) => i.value == initialValue)
                    .firstOrNull
                    ?.child ??
                const SizedBox.shrink(),
          ),
          const Icon(Icons.unfold_more_rounded, size: 20),
        ],
      ),
    ),
  );
}

class GlassAlertDialog extends StatelessWidget {
  const GlassAlertDialog({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.scrollable = false,
  });
  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;
  final bool scrollable;
  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    elevation: 0,
    insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
    child: GlassSurface(
      radius: 32,
      prominent: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null) ...[
                DefaultTextStyle(
                  style: Theme.of(context).textTheme.headlineSmall!,
                  child: title!,
                ),
                const SizedBox(height: 20),
              ],
              if (content != null)
                Flexible(
                  child: scrollable
                      ? SingleChildScrollView(child: content!)
                      : content!,
                ),
              if (actions != null) ...[
                const SizedBox(height: 20),
                OverflowBar(
                  alignment: MainAxisAlignment.end,
                  spacing: 8,
                  overflowSpacing: 8,
                  children: actions!,
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
