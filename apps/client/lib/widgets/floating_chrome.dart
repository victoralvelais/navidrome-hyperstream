import 'package:flutter/material.dart';

import 'glass_surface.dart';

class PageChrome extends InheritedWidget {
  const PageChrome({
    super.key,
    required this.topInset,
    this.compactTitle = false,
    required super.child,
  });
  final double topInset;
  final bool compactTitle;
  static bool compactTitleOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PageChrome>()?.compactTitle ??
      false;
  static double insetOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PageChrome>()?.topInset ?? 0;
  static bool present(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PageChrome>() != null;
  @override
  bool updateShouldNotify(PageChrome oldWidget) =>
      topInset != oldWidget.topInset || compactTitle != oldWidget.compactTitle;
}

class FloatingTopBar extends StatelessWidget {
  const FloatingTopBar({super.key, this.title, this.leading, this.trailing});
  final String? title;
  final Widget? leading;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    if (title == null && leading == null && trailing == null) {
      return const SizedBox.shrink();
    }
    final row = Row(
      children: [
        ?leading,
        if (title != null)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Semantics(
                header: true,
                child: Text(
                  title!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ?trailing,
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: title != null
          ? GlassSurface(
              radius: 28,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: row,
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (leading != null)
                  GlassSurface(radius: 28, child: leading!)
                else
                  const SizedBox(width: 48),
                if (trailing != null)
                  GlassSurface(radius: 28, child: trailing!),
              ],
            ),
    );
  }
}

class FloatingNavigation extends StatelessWidget {
  const FloatingNavigation({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });
  final int selectedIndex;
  final ValueChanged<int>? onSelected;
  static const destinations = [
    ('Home', Icons.home_outlined, Icons.home_rounded),
    ('Library', Icons.library_music_outlined, Icons.library_music_rounded),
    ('Search', Icons.search_rounded, Icons.search_rounded),
  ];
  @override
  Widget build(BuildContext context) => GlassSurface(
    radius: 34,
    child: Padding(
      padding: const EdgeInsets.all(5),
      child: Row(
        children: [
          for (final (index, destination) in destinations.indexed)
            Expanded(
              child: Semantics(
                selected: selectedIndex == index,
                button: true,
                label: destination.$1,
                onTap: onSelected == null ? null : () => onSelected!(index),
                child: ExcludeSemantics(
                  child: InkWell(
                    key: ValueKey('nav-${destination.$1.toLowerCase()}'),
                    borderRadius: BorderRadius.circular(28),
                    onTap: onSelected == null ? null : () => onSelected!(index),
                    child: AnimatedContainer(
                      key: ValueKey('nav-highlight-$index'),
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 160),
                      constraints: const BoxConstraints(minHeight: 54),
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 4,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        color: selectedIndex == index
                            ? Theme.of(context).colorScheme.onSurface
                                  .withValues(alpha: .12)
                            : Colors.transparent,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            selectedIndex == index
                                ? destination.$3
                                : destination.$2,
                            size: 24,
                            color: selectedIndex == index
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                          const SizedBox(height: 1),
                          Text(
                            destination.$1,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  fontSize: 12,
                                  color: selectedIndex == index
                                      ? Theme.of(context).colorScheme.primary
                                      : null,
                                  fontWeight: selectedIndex == index
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
        ],
      ),
    ),
  );
}

class FloatingAppBar extends StatelessWidget implements PreferredSizeWidget {
  const FloatingAppBar({
    super.key,
    required this.title,
    this.actions = const [],
  });
  final String title;
  final List<Widget> actions;
  @override
  Size get preferredSize => const Size.fromHeight(60);
  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: FloatingTopBar(
      title: title,
      leading: Navigator.canPop(context)
          ? IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            )
          : null,
      trailing: actions.isEmpty
          ? null
          : Row(mainAxisSize: MainAxisSize.min, children: actions),
    ),
  );
}
