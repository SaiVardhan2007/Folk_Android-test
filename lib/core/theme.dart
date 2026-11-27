import 'package:flutter/material.dart';

/// FOLK Tracker design system: a Vaishnava temple palette.
///  - Saffron (kesari): the colour of renunciation, used for actions and highlights.
///  - Maroon: the deep temple red, used for headers and emphasis.
///  - Ivory / sandalwood: warm backgrounds, easy on the eyes.
///  - Tulasi green: "present", success.
/// Standing rules: sans-serif font, text a little big and never small, content spans the full width.
const Color kPrimary = Color(0xFFC75B12); // deep saffron
const Color kMaroon = Color(0xFF6E1F2F); // temple maroon
const Color kGold = Color(0xFFB7791F); // gold (warnings, accents)
const Color kSuccess = Color(0xFF2F7D4A); // tulasi green
const Color kWarning = Color(0xFFB7791F);
const Color kDanger = Color(0xFFB3261E);

/// Text and icons that sit on a maroon/saffron brand surface (app bar, Home header, logo).
const Color kOnBrand = Colors.white;

/// Light saffron tint used for avatars on the maroon app bar.
const Color kBrandTint = Color(0xFFFFE2C8);

/// The brand gradient (maroon to saffron) used for the Home header and the logo.
const LinearGradient kBrandGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [kMaroon, Color(0xFF9A3B22), kPrimary],
);

const Color _ivory = Color(0xFFFFF8EE); // page background
const Color _sandal = Color(0xFFF7EAD6); // soft containers
const Color _line = Color(0xFFEBD9C2); // borders
const Color _ink = Color(0xFF2B1B14); // text

/// ONE knob for all text in the app: 1.0 = as designed, 1.1 = 10% bigger everywhere. (Phone accessibility font size is applied on top of this.)
const double kTextScale = 1.0;

const String kFontFamily = 'Poppins';
const List<String> kFontFallback = ['Roboto', 'sans-serif'];

ColorScheme _scheme(Brightness b) => b == Brightness.light
    ? const ColorScheme(
        brightness: Brightness.light,
        primary: kPrimary,
        onPrimary: Colors.white,
        primaryContainer: Color(0xFFFFE2C8),
        onPrimaryContainer: Color(0xFF4A1E00),
        secondary: kMaroon,
        onSecondary: Colors.white,
        secondaryContainer: Color(0xFFF6DADF),
        onSecondaryContainer: Color(0xFF3A0A14),
        tertiary: kSuccess,
        onTertiary: Colors.white,
        tertiaryContainer: Color(0xFFD7EEDD),
        onTertiaryContainer: Color(0xFF0B3A1D),
        error: kDanger,
        onError: Colors.white,
        errorContainer: Color(0xFFFADAD6),
        onErrorContainer: Color(0xFF410002),
        surface: Colors.white,
        onSurface: _ink,
        onSurfaceVariant: Color(0xFF5E4A3F),
        outline: Color(0xFF9A8576),
        outlineVariant: _line,
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: Color(0xFFFFFBF5),
        surfaceContainer: _sandal,
        surfaceContainerHigh: Color(0xFFF2E2CB),
        surfaceContainerHighest: Color(0xFFEBD9C2),
        inverseSurface: Color(0xFF3B2A22),
        onInverseSurface: Color(0xFFFFF1E2),
        inversePrimary: Color(0xFFFFB680),
        shadow: Colors.black,
        scrim: Colors.black,
      )
    : const ColorScheme(
        brightness: Brightness.dark,
        primary: Color(0xFFFFA25C),
        onPrimary: Color(0xFF3B1700),
        primaryContainer: Color(0xFF7A3508),
        onPrimaryContainer: Color(0xFFFFDCC2),
        secondary: Color(0xFFFFB3BF),
        onSecondary: Color(0xFF4A0D1B),
        secondaryContainer: Color(0xFF6E1F2F),
        onSecondaryContainer: Color(0xFFFFD9DE),
        tertiary: Color(0xFF86D4A0),
        onTertiary: Color(0xFF00391B),
        tertiaryContainer: Color(0xFF14522E),
        onTertiaryContainer: Color(0xFFC2F0D2),
        error: Color(0xFFFFB4AB),
        onError: Color(0xFF690005),
        errorContainer: Color(0xFF93000A),
        onErrorContainer: Color(0xFFFFDAD6),
        surface: Color(0xFF251A15),
        onSurface: Color(0xFFF6E8DC),
        onSurfaceVariant: Color(0xFFD5C0B2),
        outline: Color(0xFF9F8B7D),
        outlineVariant: Color(0xFF4A382E),
        surfaceContainerLowest: Color(0xFF160E0B),
        surfaceContainerLow: Color(0xFF2B1F19),
        surfaceContainer: Color(0xFF32241D),
        surfaceContainerHigh: Color(0xFF3B2B23),
        surfaceContainerHighest: Color(0xFF45332A),
        inverseSurface: Color(0xFFF6E8DC),
        onInverseSurface: Color(0xFF3B2A22),
        inversePrimary: kPrimary,
        shadow: Colors.black,
        scrim: Colors.black,
      );

/// Brand and status colours that need a different shade in light and dark mode.
/// Use `context.colors.success` (etc.) in screens, never a fixed colour.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({required this.success, required this.warning, required this.danger, required this.brand, required this.accent});
  final Color success, warning, danger, brand, accent;

  static const light = AppColors(success: kSuccess, warning: kWarning, danger: kDanger, brand: kPrimary, accent: kMaroon);
  static const dark = AppColors(
    success: Color(0xFF6FCF97),
    warning: Color(0xFFF2C14E),
    danger: Color(0xFFFF8A80),
    brand: Color(0xFFFFA25C),
    accent: Color(0xFFFFB3BF),
  );

  @override
  AppColors copyWith({Color? success, Color? warning, Color? danger, Color? brand, Color? accent}) => AppColors(
    success: success ?? this.success,
    warning: warning ?? this.warning,
    danger: danger ?? this.danger,
    brand: brand ?? this.brand,
    accent: accent ?? this.accent,
  );

  @override
  AppColors lerp(AppColors? other, double t) => other == null
      ? this
      : AppColors(
          success: Color.lerp(success, other.success, t)!,
          warning: Color.lerp(warning, other.warning, t)!,
          danger: Color.lerp(danger, other.danger, t)!,
          brand: Color.lerp(brand, other.brand, t)!,
          accent: Color.lerp(accent, other.accent, t)!,
        );
}

extension AppColorsContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = _scheme(brightness);
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: brightness, fontFamily: kFontFamily, fontFamilyFallback: kFontFallback);

  // Poppins runs wider than Roboto, so sizes are a touch smaller on the scale but still large and readable: body 16sp, nothing below ~12.5sp.
  TextStyle s(double size, FontWeight w, {double? height, double? spacing}) => TextStyle(
    fontSize: size,
    fontWeight: w,
    height: height ?? 1.35,
    letterSpacing: spacing ?? 0,
    fontFamily: kFontFamily,
    fontFamilyFallback: kFontFallback,
  );
  final textTheme = TextTheme(
    displayLarge: s(36, FontWeight.w700),
    displayMedium: s(30, FontWeight.w700),
    displaySmall: s(27, FontWeight.w700),
    headlineLarge: s(25, FontWeight.w700),
    headlineMedium: s(23, FontWeight.w700),
    headlineSmall: s(21, FontWeight.w600),
    titleLarge: s(19, FontWeight.w600),
    titleMedium: s(16.5, FontWeight.w600),
    titleSmall: s(14.5, FontWeight.w600),
    bodyLarge: s(15.5, FontWeight.w400, height: 1.45),
    bodyMedium: s(14, FontWeight.w400, height: 1.4),
    bodySmall: s(12.5, FontWeight.w400, height: 1.4),
    labelLarge: s(14.5, FontWeight.w600, spacing: 0.2),
    labelMedium: s(13, FontWeight.w500, spacing: 0.1),
    labelSmall: s(12, FontWeight.w500),
  ).apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface, fontSizeFactor: kTextScale);

  final bg = dark ? const Color(0xFF1B120E) : _ivory;
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: c, width: w),
  );
  final shape14 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));

  return base.copyWith(
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    extensions: [dark ? AppColors.dark : AppColors.light],
    scaffoldBackgroundColor: bg,
    // Plain ripple: the default sparkle effect uses a shader that costs frames on mid-range phones.
    splashFactory: InkRipple.splashFactory,
    visualDensity: const VisualDensity(horizontal: -1, vertical: -1),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: dark ? scheme.surface : kMaroon,
      foregroundColor: dark ? scheme.onSurface : Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: textTheme.titleLarge?.copyWith(color: dark ? scheme.onSurface : Colors.white),
      iconTheme: IconThemeData(color: dark ? scheme.onSurface : Colors.white),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? scheme.surfaceContainer : Colors.white,
      border: border(scheme.outlineVariant),
      enabledBorder: border(dark ? scheme.outlineVariant : const Color(0xFFD9C3A8)),
      focusedBorder: border(scheme.primary, 2),
      errorBorder: border(scheme.error),
      focusedErrorBorder: border(scheme.error, 2),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      labelStyle: textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
      floatingLabelStyle: textTheme.bodyMedium?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600),
      hintStyle: textTheme.bodyLarge?.copyWith(color: scheme.outline),
      helperStyle: textTheme.bodySmall,
      errorStyle: textTheme.bodySmall?.copyWith(color: scheme.error),
      prefixIconColor: scheme.onSurfaceVariant,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), textStyle: textTheme.labelLarge, shape: shape14, elevation: 0),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        textStyle: textTheme.labelLarge,
        shape: shape14,
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.6)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(44, 44), textStyle: textTheme.labelLarge),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: dark ? scheme.surface : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
      subtitleTextStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      iconColor: scheme.primary,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 64,
      backgroundColor: dark ? scheme.surface : Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primaryContainer,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (st) => textTheme.labelMedium?.copyWith(
          fontWeight: st.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: st.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (st) => IconThemeData(size: 24, color: st.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: dark ? scheme.surface : Colors.white,
      indicatorColor: scheme.primaryContainer,
      selectedLabelTextStyle: textTheme.labelMedium?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700),
      unselectedLabelTextStyle: textTheme.labelMedium,
    ),
    tabBarTheme: TabBarThemeData(
      labelStyle: textTheme.labelLarge,
      unselectedLabelStyle: textTheme.labelMedium,
      indicatorColor: scheme.primary,
      labelColor: scheme.primary,
      unselectedLabelColor: scheme.onSurfaceVariant,
      dividerColor: scheme.outlineVariant,
    ),
    chipTheme: ChipThemeData(
      labelStyle: textTheme.labelMedium,
      backgroundColor: scheme.surfaceContainer,
      side: BorderSide(color: scheme.outlineVariant),
      shape: const StadiumBorder(),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        textStyle: textTheme.labelMedium,
        selectedBackgroundColor: scheme.primaryContainer,
        selectedForegroundColor: scheme.onPrimaryContainer,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: shape14,
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: scheme.onInverseSurface),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dark ? scheme.surface : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      titleTextStyle: textTheme.titleLarge,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: dark ? scheme.surface : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1, thickness: 1),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? Colors.white : scheme.outline),
      trackColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? scheme.primary : scheme.surfaceContainerHighest),
    ),
  );
}
