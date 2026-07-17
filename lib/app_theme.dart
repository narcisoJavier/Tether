import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'utils/constants.dart';

/// Premium dark theme for OPA — Deep Space aesthetic.
///
/// Design language:
///   • Layered midnight-navy surfaces (3 distinct depth levels)
///   • Neon teal-green accent with bloom glow
///   • Electric blue secondary + amber / purple semantics
///   • Inter for UI text, JetBrains Mono for code/terminal
///   • Material 3 color scheme seeded from primary green
class AppTheme {
  AppTheme._();

  // ── Scaffold background gradient ──────────────────────────────────────────
  /// Two-stop linear gradient used as the Scaffold body background.
  /// Wraps the scaffold with a [Container] using this decoration.
  static const LinearGradient scaffoldGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF0A0E1A), // deep navy at top
      AppConstants.bgBase, // slightly lighter at bottom
    ],
  );

  static ThemeData dark() {
    // Override status bar to be transparent with light icons.
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppConstants.bgDeep,
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppConstants.primaryGreen,
      brightness: Brightness.dark,
      primary: AppConstants.primaryGreen,
      onPrimary: Colors.black,
      secondary: AppConstants.accentBlue,
      onSecondary: Colors.white,
      surface: AppConstants.surface1,
      onSurface: Colors.white,
      error: const Color(0xFFFF5370),
      onError: Colors.white,
    );

    // Typography
    final interBase = GoogleFonts.interTextTheme(Typography().white);
    final monoBase = GoogleFonts.jetBrainsMonoTextTheme(Typography().white);

    final interTheme = interBase.apply(
      bodyColor: Colors.white,
      displayColor: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,

      // ── Scaffold ────────────────────────────────────────────────────────
      scaffoldBackgroundColor: AppConstants.bgBase,

      // ── AppBar ──────────────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        toolbarHeight: 58,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
        titleTextStyle: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
        iconTheme: IconThemeData(
          color: Colors.white.withValues(alpha: 0.85),
          size: 22,
        ),
        actionsIconTheme: IconThemeData(
          color: Colors.white.withValues(alpha: 0.75),
          size: 22,
        ),
        surfaceTintColor: Colors.transparent,
      ),

      // ── Cards ────────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        color: AppConstants.surface1,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppConstants.border0),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),

      // ── Elevated Button ──────────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppConstants.primaryGreen,
          foregroundColor: Colors.black,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 15),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            letterSpacing: 0.3,
          ),
        ),
      ),

      // ── Outlined Button ──────────────────────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppConstants.accentBlue,
          side: const BorderSide(color: AppConstants.accentBlue, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),

      // ── Text Button ──────────────────────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppConstants.primaryGreen,
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),

      // ── FAB ──────────────────────────────────────────────────────────────
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppConstants.primaryGreen,
        foregroundColor: Colors.black,
        elevation: 6,
        highlightElevation: 10,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        extendedPadding: const EdgeInsets.symmetric(horizontal: 24),
        extendedTextStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w700,
          fontSize: 14,
          letterSpacing: 0.5,
        ),
      ),

      // ── Input Decoration ─────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppConstants.inputFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppConstants.border0),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppConstants.border0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: AppConstants.primaryGreen,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Color(0xFFFF5370),
            width: 1.2,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Color(0xFFFF5370),
            width: 1.5,
          ),
        ),
        hintStyle: GoogleFonts.inter(
          color: Colors.white.withValues(alpha: 0.28),
          fontSize: 14,
        ),
        labelStyle: GoogleFonts.inter(
          color: Colors.white.withValues(alpha: 0.55),
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
        floatingLabelStyle: GoogleFonts.inter(
          color: AppConstants.primaryGreen,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        prefixIconColor: Colors.white.withValues(alpha: 0.45),
        suffixIconColor: Colors.white.withValues(alpha: 0.45),
      ),

      // ── List Tile ────────────────────────────────────────────────────────
      listTileTheme: const ListTileThemeData(
        tileColor: Colors.transparent,
        textColor: Colors.white,
        iconColor: AppConstants.primaryGreen,
        contentPadding: EdgeInsets.symmetric(horizontal: 20),
        minLeadingWidth: 28,
      ),

      // ── Divider ──────────────────────────────────────────────────────────
      dividerTheme: const DividerThemeData(
        color: AppConstants.border0,
        thickness: 1,
        space: 1,
      ),

      // ── SnackBar ─────────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppConstants.surface2,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: AppConstants.primaryGreen.withValues(alpha: 0.2),
          ),
        ),
        contentTextStyle: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 14,
        ),
        elevation: 8,
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),

      // ── Bottom Sheet ─────────────────────────────────────────────────────
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppConstants.surface2,
        modalBackgroundColor: AppConstants.surface2,
        modalBarrierColor: Colors.black.withValues(alpha: 0.7),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        dragHandleColor: Colors.white.withValues(alpha: 0.2),
        dragHandleSize: const Size(40, 4),
        showDragHandle: true,
        elevation: 12,
      ),

      // ── Dialog ───────────────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: AppConstants.surface2,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppConstants.border1),
        ),
        elevation: 16,
        titleTextStyle: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
        contentTextStyle: GoogleFonts.inter(
          color: Colors.white.withValues(alpha: 0.7),
          fontSize: 14,
          height: 1.5,
        ),
      ),

      // ── Popup Menu ───────────────────────────────────────────────────────
      popupMenuTheme: PopupMenuThemeData(
        color: AppConstants.surface2,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppConstants.border0),
        ),
        textStyle: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 14,
        ),
      ),

      // ── Chip ─────────────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: AppConstants.surface1,
        selectedColor: AppConstants.primaryGreen.withValues(alpha: 0.15),
        side: const BorderSide(color: AppConstants.border0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        labelStyle: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),

      // ── Switch ───────────────────────────────────────────────────────────
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.black;
          }
          return Colors.white.withValues(alpha: 0.5);
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppConstants.primaryGreen;
          }
          return Colors.white.withValues(alpha: 0.1);
        }),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),

      // ── Slider ───────────────────────────────────────────────────────────
      sliderTheme: SliderThemeData(
        activeTrackColor: AppConstants.primaryGreen,
        inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
        thumbColor: AppConstants.primaryGreen,
        overlayColor: AppConstants.primaryGreen.withValues(alpha: 0.12),
        trackHeight: 3,
      ),

      // ── Progress Indicator ───────────────────────────────────────────────
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppConstants.primaryGreen,
        circularTrackColor: AppConstants.border0,
      ),

      // ── Icon ─────────────────────────────────────────────────────────────
      iconTheme: const IconThemeData(
        color: AppConstants.primaryGreen,
        size: 24,
      ),

      // ── Scrollbar ────────────────────────────────────────────────────────
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(
          Colors.white.withValues(alpha: 0.15),
        ),
        radius: const Radius.circular(4),
        thickness: WidgetStateProperty.all(3),
      ),

      // ── Typography ───────────────────────────────────────────────────────
      fontFamily: GoogleFonts.inter().fontFamily,
      textTheme: TextTheme(
        displayLarge: monoBase.displayLarge?.copyWith(color: Colors.white),
        displayMedium: monoBase.displayMedium?.copyWith(color: Colors.white),
        displaySmall: monoBase.displaySmall?.copyWith(color: Colors.white),
        headlineLarge: interTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w800),
        headlineMedium: interTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
        headlineSmall: interTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        titleLarge: interTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        titleMedium: interTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        titleSmall: interTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        bodyLarge: interTheme.bodyLarge,
        bodyMedium: interTheme.bodyMedium,
        bodySmall: interTheme.bodySmall?.copyWith(
          color: Colors.white.withValues(alpha: 0.55),
        ),
        labelLarge: interTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        labelMedium: interTheme.labelMedium?.copyWith(fontWeight: FontWeight.w500),
        labelSmall: interTheme.labelSmall?.copyWith(
          color: Colors.white.withValues(alpha: 0.55),
        ),
      ),
    );
  }
}

// ── Reusable Design Helpers ───────────────────────────────────────────────────

/// A gradient + border box decoration for premium glass-like containers.
class GlassDecoration {
  GlassDecoration._();

  /// Card-level glass — subtle gradient background with fine border.
  static BoxDecoration card({
    Color? accentColor,
    double borderRadius = 16,
    bool highlighted = false,
  }) {
    final accent = accentColor ?? AppConstants.primaryGreen;
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppConstants.surface1.withValues(alpha: highlighted ? 1.0 : 0.95),
          AppConstants.surface0.withValues(alpha: highlighted ? 1.0 : 0.9),
        ],
      ),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: highlighted
            ? accent.withValues(alpha: 0.25)
            : AppConstants.border0,
        width: highlighted ? 1.2 : 1.0,
      ),
      boxShadow: highlighted
          ? [
              BoxShadow(
                color: accent.withValues(alpha: 0.08),
                blurRadius: 20,
                spreadRadius: 0,
                offset: const Offset(0, 4),
              ),
            ]
          : null,
    );
  }

  /// Sheet-level glass — for bottom sheets and modals.
  static BoxDecoration sheet({double borderRadius = 24}) => BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppConstants.surface2,
            AppConstants.surface1,
          ],
        ),
        borderRadius: BorderRadius.circular(borderRadius),
        border: const Border(
          top: BorderSide(color: AppConstants.border1),
          left: BorderSide(color: AppConstants.border0),
          right: BorderSide(color: AppConstants.border0),
        ),
      );
}

/// Neon glow shadow — used on accent elements.
class NeonGlow {
  NeonGlow._();

  static List<BoxShadow> of(Color color, {double intensity = 1.0}) => [
        BoxShadow(
          color: color.withValues(alpha: 0.35 * intensity),
          blurRadius: 12 * intensity,
          spreadRadius: 0,
        ),
        BoxShadow(
          color: color.withValues(alpha: 0.15 * intensity),
          blurRadius: 24 * intensity,
          spreadRadius: 2,
        ),
      ];

  static List<BoxShadow> dot(Color color) => [
        BoxShadow(
          color: color.withValues(alpha: 0.6),
          blurRadius: 6,
          spreadRadius: 1,
        ),
      ];
}
