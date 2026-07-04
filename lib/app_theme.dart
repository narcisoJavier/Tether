import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'utils/constants.dart';

/// Dark terminal-inspired theme for OPA.
class AppTheme {
  AppTheme._();

  static ThemeData dark() {
    const bgColor = Colors.black;
    const surfaceColor = Colors.black;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppConstants.primaryGreen,
      brightness: Brightness.dark,
      surface: surfaceColor,
    );

    // Typography — Inter for UI, JetBrains Mono for terminal/code.
    final interTextTheme = GoogleFonts.interTextTheme(
      Typography().white,
    );
    final monoTextTheme = GoogleFonts.jetBrainsMonoTextTheme(
      Typography().white,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bgColor,
      appBarTheme: AppBarTheme(
        backgroundColor: surfaceColor,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        toolbarHeight: 52,
        titleTextStyle: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
        iconTheme: IconThemeData(color: Colors.white.withValues(alpha: 0.8)),
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: surfaceColor.withValues(alpha: 0.8),
        elevation: 2,
        shadowColor: AppConstants.primaryGreen.withValues(alpha: 0.05),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppConstants.primaryGreen,
          foregroundColor: Colors.black,
          elevation: 2,
          shadowColor: AppConstants.primaryGreen.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF448AFF),
          side: const BorderSide(color: Color(0xFF448AFF), width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppConstants.primaryGreen,
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppConstants.primaryGreen,
        foregroundColor: Colors.black,
        elevation: 4,
        highlightElevation: 8,
        shape: CircleBorder(),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppConstants.inputFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: AppConstants.primaryGreen,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: Colors.red.withValues(alpha: 0.5),
          ),
        ),
        hintStyle: GoogleFonts.inter(
          color: Colors.white.withValues(alpha: 0.35),
        ),
        labelStyle: GoogleFonts.inter(
          color: Colors.white.withValues(alpha: 0.5),
          fontWeight: FontWeight.w500,
        ),
        prefixIconColor: Colors.white.withValues(alpha: 0.5),
        suffixIconColor: Colors.white.withValues(alpha: 0.5),
      ),
      listTileTheme: const ListTileThemeData(
        textColor: Colors.white,
        iconColor: AppConstants.primaryGreen,
      ),
      dividerTheme: DividerThemeData(
        color: Colors.white.withValues(alpha: 0.06),
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: AppConstants.primaryGreen.withValues(alpha: 0.15),
          ),
        ),
        elevation: 4,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surfaceColor.withValues(alpha: 0.95),
        modalBarrierColor: Colors.black54,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        elevation: 8,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
        elevation: 8,
        titleTextStyle: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: GoogleFonts.inter(
          color: Colors.white.withValues(alpha: 0.7),
          fontSize: 14,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surfaceColor,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
        textStyle: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 14,
        ),
      ),
      fontFamily: 'Inter',
      textTheme: TextTheme(
        displayLarge: monoTextTheme.displayLarge,
        displayMedium: monoTextTheme.displayMedium,
        displaySmall: monoTextTheme.displaySmall,
        headlineLarge: interTextTheme.headlineLarge,
        headlineMedium: interTextTheme.headlineMedium,
        headlineSmall: interTextTheme.headlineSmall,
        titleLarge: interTextTheme.titleLarge,
        titleMedium: interTextTheme.titleMedium,
        titleSmall: interTextTheme.titleSmall,
        bodyLarge: interTextTheme.bodyLarge,
        bodyMedium: interTextTheme.bodyMedium?.copyWith(
          color: Colors.white,
          fontFamily: 'JetBrainsMono',
        ),
        bodySmall: interTextTheme.bodySmall,
        labelLarge: interTextTheme.labelLarge,
        labelMedium: interTextTheme.labelMedium,
        labelSmall: interTextTheme.labelSmall,
      ),
    );
  }
}
