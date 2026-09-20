import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';

// Colors and text styles shared by the views, all derived from the macOS
// theme so light and dark mode and the system accent just work.

// Skill set palette, by the slot a set stores: blue, purple, green, pink,
// orange, red.
const _setPalette = <Color>[
  MacosColors.systemBlueColor,
  MacosColors.systemPurpleColor,
  MacosColors.systemGreenColor,
  MacosColors.systemPinkColor,
  MacosColors.systemOrangeColor,
  MacosColors.systemRedColor,
];

extension CabinetStyle on BuildContext {
  MacosThemeData get macos => MacosTheme.of(this);
  bool get isDark => macos.brightness == Brightness.dark;
  Color get accent => macos.primaryColor;

  // Flutter's resolver: macos_ui's leaves Cupertino colors unresolved
  // (always their light variant).
  Color setColor(int slot) => resolve(_setPalette[slot % _setPalette.length]);
  Color resolve(Color color) => CupertinoDynamicColor.resolve(color, this);

  Color get label => resolve(CupertinoColors.label);
  Color get secondaryLabel => resolve(CupertinoColors.secondaryLabel);
  Color get tertiaryLabel => resolve(CupertinoColors.tertiaryLabel);
  Color get separator => isDark ? const Color(0x1FFFFFFF) : const Color(0x1A000000);

  // Row washes: hover, selection, and a card surface over the canvas.
  Color get hoverFill => isDark ? const Color(0x0DFFFFFF) : const Color(0x0A000000);
  Color get selectedFill => accent.withValues(alpha: isDark ? 0.22 : 0.13);
  Color get sidebarSelectedFill => isDark ? const Color(0x1FFFFFFF) : const Color(0x14000000);
  Color get cardFill => isDark ? const Color(0x0AFFFFFF) : const Color(0x08000000);

  TextStyle get body => macos.typography.body;
  TextStyle get callout => macos.typography.callout;
  TextStyle get caption => macos.typography.caption1.copyWith(color: secondaryLabel);
  TextStyle get sectionLabel =>
      macos.typography.caption1.copyWith(color: tertiaryLabel, fontWeight: FontWeight.w600, letterSpacing: 0.2);
  TextStyle get placeholder => body.copyWith(color: secondaryLabel.withValues(alpha: 0.45));
  TextStyle get mono => macos.typography.caption1.copyWith(fontFamily: 'Menlo', color: secondaryLabel);
}
