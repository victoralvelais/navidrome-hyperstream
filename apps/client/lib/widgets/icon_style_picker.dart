import 'package:flutter/material.dart';

import '../models/icon_style.dart';
import 'app_icon.dart';

/// Samples use their own family; the rest of the app follows the live choice.
class IconStylePicker extends StatelessWidget {
  const IconStylePicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final IconStyle value;
  final ValueChanged<IconStyle> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final style in IconStyle.values) ...[
        if (style != IconStyle.values.first)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Divider(height: 1),
          ),
        Semantics(
          selected: value == style,
          inMutuallyExclusiveGroup: true,
          child: ListTile(
            key: ValueKey('icon-style-${style.name}'),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 10,
            ),
            title: Text(style.label),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 4),
              child: ExcludeSemantics(
                child: Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  children: [
                    for (final symbol in const [
                      Icons.home_outlined,
                      Icons.library_music_outlined,
                      Icons.play_arrow_rounded,
                      Icons.favorite_border_rounded,
                      Icons.volume_up_rounded,
                      Icons.public_rounded,
                    ])
                      AppIcon(symbol, style: style, size: 24),
                  ],
                ),
              ),
            ),
            selected: value == style,
            trailing: SizedBox.square(
              dimension: 24,
              child: value == style ? const AppIcon(Icons.check_rounded) : null,
            ),
            onTap: () => onChanged(style),
          ),
        ),
      ],
    ],
  );
}
