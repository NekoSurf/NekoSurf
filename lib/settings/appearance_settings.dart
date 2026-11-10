import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/settings/settings_widgets.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/dash_menu.dart';
import 'package:provider/provider.dart';

/// Light or dark, and the theme's color.
class AppearanceSettings extends StatelessWidget {
  const AppearanceSettings({super.key});

  static const Map<Appearance, String> _titles = {
    Appearance.system: 'Auto',
    Appearance.light: 'Light',
    Appearance.dark: 'Dark',
  };

  /// The least room between swatches.
  static const double _minGap = 8;

  static const Map<Appearance, IconData> _icons = {
    Appearance.system: CupertinoIcons.circle_lefthalf_fill,
    Appearance.light: CupertinoIcons.sun_max_fill,
    Appearance.dark: CupertinoIcons.moon_fill,
  };

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);

    final bool isAlwaysDark = settings.themeColor.value.isAlwaysDark;

    return SettingsGroup(
      title: 'Theme',
      footer: "Auto follows your phone's light or dark mode.",
      children: [
        if (isAlwaysDark)
          const SettingsRow(
            icon: CupertinoIcons.circle_lefthalf_fill,
            color: Color(0xFF60A5FA),
            title: 'Appearance',
            subtitle: 'OLED is always dark',
            value: 'Dark',
          )
        else
          DashMenuAnchor(
            menuChildren: [
              for (final Appearance appearance in Appearance.values)
                DashMenuEntry(
                  title: _titles[appearance]!,
                  icon: _icons[appearance],
                  isSelected: settings.appearance.value == appearance,
                  onPressed: () => settings.appearance.set(appearance),
                ),
            ],
            builder: (context, open) => SettingsRow(
              icon: CupertinoIcons.circle_lefthalf_fill,
              color: const Color(0xFF60A5FA),
              title: 'Appearance',
              value: _titles[settings.appearance.value],
              onTap: open,
            ),
          ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsRow(
              icon: CupertinoIcons.paintbrush_fill,
              color: context.accent,
              title: 'Color',
              value: settings.themeColor.value.title,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 2, 14, 14),
              // As many to a row as fit, spread across it, so the rows line up.
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const double size = ThemeSwatch.size;
                  final int perRow = max(
                    1,
                    (constraints.maxWidth + _minGap) ~/ (size + _minGap),
                  );
                  return Wrap(
                    spacing: perRow > 1
                        ? (constraints.maxWidth - perRow * size) / (perRow - 1)
                        : 0,
                    runSpacing: 10,
                    children: [
                      for (final ThemeColor theme in ThemeColor.values)
                        ThemeSwatch(
                          theme: theme,
                          selected: theme == settings.themeColor.value,
                          onTap: () => settings.themeColor.set(theme),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A theme to choose: its two colors, blended in a circle.
class ThemeSwatch extends StatelessWidget {
  const ThemeSwatch({
    super.key,
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final ThemeColor theme;
  final bool selected;
  final VoidCallback onTap;

  static const double size = 34;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: theme.title,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? theme.accent : const Color(0x00000000),
              width: 2,
            ),
          ),
          // OLED's is its black, with a gleam of its accent and an edge to see
          // it by on a dark card.
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: theme.isAlwaysDark
                  ? Border.all(color: const Color(0x40FFFFFF))
                  : null,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: theme.isAlwaysDark
                    ? [
                        CupertinoColors.black,
                        CupertinoColors.black,
                        theme.accent,
                      ]
                    : [theme.accent, theme.accent, theme.accent2],
                stops: theme.isAlwaysDark
                    ? const [0, 0.6, 1.4]
                    : const [0, 0.45, 1],
              ),
            ),
            child: selected
                ? Icon(
                    CupertinoIcons.check_mark,
                    size: 14,
                    color: theme.isAlwaysDark
                        ? CupertinoColors.white
                        : CupertinoColors.black,
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
