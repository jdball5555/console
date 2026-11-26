// Console's look: black and white, hairline borders, almost no color.
// Red is only for destructive actions and errors.

import 'package:flutter/material.dart';

const kBg = Color(0xFF000000);
const kSurface = Color(0xFF111113);
const kSurfaceHigh = Color(0xFF1C1C1F);
const kLine = Color(0xFF26262A);

const kText = Color(0xFFFFFFFF);
const kTextDim = Color(0xFFA1A1A6);
const kTextFaint = Color(0xFF636366);

/// Delete, block, errors. Nothing else.
const kDanger = Color(0xFFE5484D);

ThemeData buildConsoleTheme() {
  const scheme = ColorScheme.dark(
    primary: kText,
    onPrimary: kBg,
    secondary: kText,
    onSecondary: kBg,
    surface: kSurface,
    onSurface: kText,
    surfaceContainerHighest: kSurfaceHigh,
    outline: kLine,
    outlineVariant: kLine,
    error: kDanger,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: Brightness.dark);
  return base.copyWith(
    scaffoldBackgroundColor: kBg,
    canvasColor: kBg,
    cardColor: kSurface,
    dividerColor: kLine,
    splashFactory: InkSparkle.splashFactory,
    textTheme: base.textTheme.apply(bodyColor: kText, displayColor: kText),
    dividerTheme: const DividerThemeData(color: kLine, thickness: 0.6, space: 0.6),
    appBarTheme: const AppBarTheme(
      backgroundColor: kBg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: kText, letterSpacing: -0.2),
      iconTheme: IconThemeData(color: kText),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: kText,
      unselectedLabelColor: kTextFaint,
      indicatorColor: kText,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: kLine,
      labelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kText,
        foregroundColor: kBg,
        disabledBackgroundColor: kSurfaceHigh,
        disabledForegroundColor: kTextFaint,
        shape: shape,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kText,
        side: const BorderSide(color: kLine),
        shape: shape,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: kText, shape: shape),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: kText)),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? kText : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? kBg : kTextDim,
        ),
        side: const WidgetStatePropertyAll(BorderSide(color: kLine)),
        shape: WidgetStatePropertyAll(shape),
        textStyle: const WidgetStatePropertyAll(TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        visualDensity: VisualDensity.compact,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.transparent,
      selectedColor: kText,
      side: const BorderSide(color: kLine),
      labelStyle: const TextStyle(color: kTextDim, fontWeight: FontWeight.w600, fontSize: 13),
      secondaryLabelStyle: const TextStyle(color: kBg, fontWeight: FontWeight.w600, fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
      showCheckmark: false,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? kBg : kTextDim),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? kText : kSurfaceHigh),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? kText : kLine,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kSurface,
      hintStyle: const TextStyle(color: kTextFaint),
      labelStyle: const TextStyle(color: kTextDim),
      floatingLabelStyle: const TextStyle(color: kText),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kLine)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kLine),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kText, width: 1),
      ),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: kText,
      selectionColor: Color(0x55FFFFFF),
      selectionHandleColor: kText,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: kText),
    dialogTheme: DialogThemeData(
      backgroundColor: kSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: kSurface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: kLine,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: kSurfaceHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    listTileTheme: const ListTileThemeData(iconColor: kTextDim),
    badgeTheme: const BadgeThemeData(backgroundColor: kText, textColor: kBg),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: FadeForwardsPageTransitionsBuilder()},
    ),
  );
}

/// Small uppercase label over a group of rows.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.padding = const EdgeInsets.fromLTRB(4, 28, 4, 10)});
  final String text;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(color: kTextFaint, fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 1.4),
    ),
  );
}

/// A rounded group with hairline border.
BoxDecoration panelDecoration({double radius = 16}) => BoxDecoration(
  color: kSurface,
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: kLine, width: 0.8),
);
