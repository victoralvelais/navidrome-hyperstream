import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/icon_style.dart';

part 'app_icon_data.dart';

/// Above the Navigator so sheets, dialogs and already-open routes update too.
class AppIconTheme extends InheritedWidget {
  const AppIconTheme({super.key, required this.style, required super.child});

  final IconStyle style;

  static IconStyle of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppIconTheme>()?.style ??
      IconStyle.iconoir;

  @override
  bool updateShouldNotify(AppIconTheme oldWidget) => style != oldWidget.style;
}

/// Existing Material symbols identify actions, not their visual appearance.
/// Extending Icon preserves Flutter's icon inspection and widget-test finders.
class AppIcon extends Icon {
  const AppIcon(
    super.icon, {
    super.key,
    super.size,
    super.color,
    super.semanticLabel,
    super.textDirection,
    super.applyTextScaling,
    this.style,
  });

  /// Used by the style picker to preview a family without changing the app.
  final IconStyle? style;

  static Iterable<IconData> get supportedIcons => _iconBindings.keys;

  static String? assetFor(IconData? icon, IconStyle style) {
    final binding = _iconBindings[icon];
    if (binding == null) return null;
    if (style == IconStyle.cupertino && binding.cupertino != null) return null;
    final family = style == IconStyle.cupertino ? IconStyle.iconoir : style;
    return 'assets/icons/${family.name}/${binding.name}.svg';
  }

  @override
  Widget build(BuildContext context) {
    final selectedStyle = style ?? AppIconTheme.of(context);
    final binding = _iconBindings[icon];
    if (binding == null) return super.build(context);
    if (selectedStyle == IconStyle.cupertino && binding.cupertino != null) {
      return Icon(
        binding.cupertino,
        size: size,
        color: color,
        semanticLabel: semanticLabel,
        textDirection: textDirection,
        applyTextScaling: applyTextScaling,
      );
    }
    final theme = IconTheme.of(context);
    var extent = size ?? theme.size ?? 24;
    if (applyTextScaling ?? theme.applyTextScaling ?? false) {
      extent = MediaQuery.textScalerOf(context).scale(extent);
    }
    var tint = color ?? theme.color ?? Theme.of(context).colorScheme.onSurface;
    tint = tint.withValues(alpha: tint.a * (theme.opacity ?? 1));
    final direction = textDirection ?? Directionality.of(context);
    return Semantics(
      label: semanticLabel,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: extent,
          child: Directionality(
            textDirection: direction,
            child: SvgPicture.asset(
              assetFor(icon, selectedStyle)!,
              width: extent,
              height: extent,
              colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
              matchTextDirection: icon!.matchTextDirection,
              excludeFromSemantics: true,
            ),
          ),
        ),
      ),
    );
  }
}

class _IconBinding {
  const _IconBinding(this.name, this.cupertino);
  final String name;
  final IconData? cupertino;
}
