import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'glass.dart';

/// Glass-morphism theme matching the iOS admin app. Scaffolds are transparent;
/// [GlassPageTransitionsBuilder] paints the colour field behind each page.
abstract final class AdminTheme {
  static const seed = Brand.primary;

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final ink = isDark ? Brand.inkDark : Brand.ink;
    final muted = isDark ? Brand.mutedDark : Brand.muted;
    final colors = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      primary: isDark ? const Color(0xFF6B9BFF) : seed,
      secondary: Brand.violet,
      error: Brand.danger,
      surface: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFF),
      onSurface: ink,
      onSurfaceVariant: muted,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: colors);
    // GoogleFonts.x() returns styles with a null color; without re-applying the
    // scheme colors below they resolve to white and vanish on light surfaces.
    final text = GoogleFonts.plusJakartaSansTextTheme(base.textTheme)
        .copyWith(
          displaySmall: GoogleFonts.plusJakartaSans(
            fontSize: 34,
            fontWeight: FontWeight.w800,
          ),
          headlineLarge: GoogleFonts.plusJakartaSans(
            fontSize: 28,
            fontWeight: FontWeight.w800,
          ),
          headlineMedium: GoogleFonts.plusJakartaSans(
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
          titleLarge: GoogleFonts.plusJakartaSans(
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
          titleMedium: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
          bodyLarge: GoogleFonts.plusJakartaSans(fontSize: 15.5),
          bodyMedium: GoogleFonts.plusJakartaSans(fontSize: 14.5),
          bodySmall: GoogleFonts.plusJakartaSans(fontSize: 12.5),
          labelLarge: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        )
        .apply(bodyColor: ink, displayColor: ink);

    final glassFill = isDark
        ? const Color(0xFF1E293B).withValues(alpha: 0.72)
        : Colors.white.withValues(alpha: 0.62);
    final glassBorder = BorderSide(
      color: isDark
          ? Colors.white.withValues(alpha: 0.1)
          : Colors.white.withValues(alpha: 0.9),
    );
    final solidSurface = isDark
        ? const Color(0xFF172033)
        : Colors.white.withValues(alpha: 0.95);
    final pill = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(40),
    );
    final field = OutlineInputBorder(
      borderRadius: BorderRadius.circular(GlassMetrics.smallRadius),
      borderSide: glassBorder,
    );
    const transitions = GlassPageTransitionsBuilder();
    final overlay = isDark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;

    return base.copyWith(
      textTheme: text,
      scaffoldBackgroundColor: Colors.transparent,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: transitions,
          TargetPlatform.iOS: transitions,
          TargetPlatform.windows: transitions,
          TargetPlatform.macOS: transitions,
          TargetPlatform.linux: transitions,
          TargetPlatform.fuchsia: transitions,
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: overlay.copyWith(
          statusBarColor: Colors.transparent,
        ),
        titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
      listTileTheme: ListTileThemeData(
        textColor: ink,
        iconColor: muted,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(GlassMetrics.smallRadius),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: glassFill,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GlassMetrics.radius),
          side: glassBorder,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: glassFill,
        border: field,
        enabledBorder: field,
        focusedBorder: field.copyWith(
          borderSide: BorderSide(color: colors.primary, width: 1.6),
        ),
        errorBorder: field.copyWith(
          borderSide: const BorderSide(color: Brand.danger),
        ),
        focusedErrorBorder: field.copyWith(
          borderSide: const BorderSide(color: Brand.danger, width: 1.6),
        ),
        labelStyle: text.bodyMedium?.copyWith(color: muted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 50),
          shape: pill,
          elevation: 0,
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 50),
          shape: pill,
          backgroundColor: isDark
              ? Colors.white.withValues(alpha: 0.04)
              : Colors.white.withValues(alpha: 0.55),
          side: glassBorder,
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: pill),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: glassFill,
        side: glassBorder,
        shape: const StadiumBorder(),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: glassFill,
          selectedBackgroundColor: colors.primary.withValues(alpha: 0.18),
          side: glassBorder,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: solidSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark
            ? const Color(0xFF172033)
            : Colors.white.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        indicatorColor: colors.primary.withValues(alpha: 0.18),
        labelTextStyle: WidgetStatePropertyAll(
          text.bodySmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: isDark
            ? const Color(0xFF0F172A).withValues(alpha: 0.6)
            : Colors.white.withValues(alpha: 0.5),
        indicatorColor: colors.primary.withValues(alpha: 0.18),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark
            ? const Color(0xFF334155)
            : Brand.ink.withValues(alpha: 0.92),
        contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerColor: glassBorder.color,
      dividerTheme: DividerThemeData(color: glassBorder.color, thickness: 1),
    );
  }
}
