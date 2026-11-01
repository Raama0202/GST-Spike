import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'glass.dart';

/// Glass-morphism Material 3 theme matching the iOS apps. Screens are
/// transparent; [GlassPageTransitionsBuilder] paints the colour field per page.
class AppTheme {
  AppTheme._();

  static ThemeData light({Color? brandPrimary}) =>
      _build(Brightness.light, brandPrimary);

  static ThemeData dark({Color? brandPrimary}) =>
      _build(Brightness.dark, brandPrimary);

  static ThemeData _build(Brightness brightness, Color? brandPrimary) {
    final isDark = brightness == Brightness.dark;
    final seed = brandPrimary ?? Brand.primary;
    final ink = isDark ? GlassPalette.darkInk : Brand.ink;
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      primary: isDark ? Color.lerp(seed, Colors.white, 0.18) : seed,
      secondary: Brand.violet,
      tertiary: Brand.warning,
      error: Brand.danger,
      surface: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFF),
    );
    final primary = scheme.primary;

    final base = GoogleFonts.plusJakartaSansTextTheme(
      isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
    );
    final textTheme = base.copyWith(
      displayLarge: base.displayLarge?.copyWith(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        height: 1.15,
        color: ink,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        color: ink,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800,
        color: ink,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      bodyLarge: base.bodyLarge?.copyWith(
        fontSize: 17,
        height: 1.4,
        color: ink,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        fontSize: 15,
        height: 1.4,
        color: ink,
      ),
      bodySmall: base.bodySmall?.copyWith(
        color: isDark ? GlassPalette.darkMuted : Brand.muted,
      ),
      labelLarge: base.labelLarge?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
    );

    final glassFill = isDark
        ? const Color(0xFF1E293B).withValues(alpha: 0.72)
        : Colors.white.withValues(alpha: 0.62);
    final glassBorder = BorderSide(
      color: isDark
          ? Colors.white.withValues(alpha: 0.10)
          : Colors.white.withValues(alpha: 0.9),
    );
    final sheetColor = isDark
        ? const Color(0xFF1E293B).withValues(alpha: 0.97)
        : Colors.white.withValues(alpha: 0.96);
    final pill = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(40),
    );
    final field = OutlineInputBorder(
      borderRadius: BorderRadius.circular(GlassMetrics.smallRadius),
      borderSide: glassBorder,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: Colors.transparent,
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: GlassPageTransitionsBuilder(),
          TargetPlatform.iOS: GlassPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: ink,
        systemOverlayStyle:
            (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
                .copyWith(statusBarColor: Colors.transparent),
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          textStyle: textTheme.labelLarge,
          shape: pill,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          textStyle: textTheme.labelLarge,
          shape: pill,
          backgroundColor: isDark
              ? const Color(0xFF1E293B).withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.55),
          foregroundColor: primary,
          side: glassBorder,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: textTheme.labelLarge,
          shape: pill,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: glassFill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        border: field,
        enabledBorder: field,
        focusedBorder: field.copyWith(
          borderSide: BorderSide(color: primary, width: 1.6),
        ),
        errorBorder: field.copyWith(
          borderSide: const BorderSide(color: Brand.danger),
        ),
        focusedErrorBorder: field.copyWith(
          borderSide: const BorderSide(color: Brand.danger, width: 1.6),
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: isDark ? GlassPalette.darkMuted : Brand.muted,
        ),
        floatingLabelStyle: textTheme.bodyMedium?.copyWith(
          color: primary,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: glassFill,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GlassMetrics.radius),
          side: glassBorder,
        ),
      ),
      listTileTheme: const ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(GlassMetrics.smallRadius),
          ),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: glassFill,
        side: glassBorder,
        shape: const StadiumBorder(),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: sheetColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: sheetColor,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: glassFill,
      ),
      dividerTheme: DividerThemeData(
        color: glassBorder.color,
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark
            ? const Color(0xFF334155)
            : Brand.ink.withValues(alpha: 0.92),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
