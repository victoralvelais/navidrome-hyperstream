/// Stable preference IDs. Keep names when changing the displayed labels.
enum IconStyle {
  iconoir('Iconoir'),
  cupertino('Cupertino'),
  phosphorLight('Phosphor Light'),
  lucide('Lucide'),
  solarLinear('Solar · Linear'),
  solarOutline('Solar · Outline'),
  solarBroken('Solar · Broken'),
  solarLineDuotone('Solar · Line duotone'),
  solarBold('Solar · Bold'),
  solarBoldDuotone('Solar · Bold duotone');

  const IconStyle(this.label);
  final String label;

  static IconStyle restore(Object? name) =>
      values.firstWhere((style) => style.name == name, orElse: () => iconoir);
}
