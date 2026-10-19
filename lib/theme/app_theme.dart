import 'package:flutter/material.dart';

/// Shared palette and component styling for BrewVerse.
abstract final class AppTheme {
  // Emerald surfaces are scoped to the redesigned dashboard first. Other
  // screens keep their existing palette until their own redesign milestone.
  static const forest = Color(0xFF103D31);
  static const emerald = Color(0xFF176B50);
  static const emeraldBright = Color(0xFF22845F);
  static const orange = Color(0xFFEF9148);
  static const orangeDeep = Color(0xFFC96B35);
  static const paper = Color(0xFFF6F4EC);
  static const card = Color(0xFFFFFEFA);
  static const ink = Color(0xFF19372F);
  static const mutedInk = Color(0xFF718078);
  static const softGreen = Color(0xFFE7F1EA);
  static const softOrange = Color(0xFFFFEFE1);
  static const line = Color(0xFFE4E9E1);

  static const charcoal = Color(0xFF171513);
  static const espresso = Color(0xFF241B17);
  static const coffee = Color(0xFF30231D);
  static const coffeeRaised = Color(0xFF3A2920);
  static const caramel = Color(0xFFE5A365);
  static const copper = Color(0xFFC7794D);
  static const cream = Color(0xFFF5E9DD);
  static const mutedCream = Color(0xFFBDA99A);
  static const sage = Color(0xFF9BB8A0);

  static final ThemeData dark = _buildDarkTheme();
  static final ThemeData emeraldLight = _buildEmeraldTheme();

  static ThemeData _buildEmeraldTheme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: emerald,
      brightness: Brightness.light,
      surface: card,
    ).copyWith(
      primary: emerald,
      onPrimary: Colors.white,
      secondary: orange,
      onSecondary: forest,
      surface: card,
      onSurface: ink,
      outline: line,
      error: const Color(0xFFB64035),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: paper,
      canvasColor: paper,
      dividerColor: line,
      appBarTheme: const AppBarTheme(
        backgroundColor: paper,
        foregroundColor: ink,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: forest,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: line),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        height: 64,
        backgroundColor: paper,
        indicatorColor: softOrange,
        elevation: 0,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: paper,
        labelStyle: const TextStyle(color: mutedInk),
        hintStyle: const TextStyle(color: mutedInk),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: _emeraldInputBorder(line),
        enabledBorder: _emeraldInputBorder(line),
        focusedBorder: _emeraldInputBorder(emerald, width: 1.5),
        errorBorder: _emeraldInputBorder(const Color(0xFFB64035)),
        focusedErrorBorder:
            _emeraldInputBorder(const Color(0xFFB64035), width: 1.5),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: emerald,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: forest,
          fontSize: 32,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.1,
          height: 1.08,
        ),
        headlineMedium: TextStyle(
          color: forest,
          fontSize: 25,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.7,
        ),
        titleLarge: TextStyle(
          color: ink,
          fontSize: 19,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: TextStyle(
          color: ink,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: TextStyle(color: ink, fontSize: 14),
        bodyMedium: TextStyle(color: mutedInk, fontSize: 13),
      ),
      iconTheme: const IconThemeData(color: emerald),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: emerald,
        linearTrackColor: softGreen,
      ),
    );
  }

  static ThemeData _buildDarkTheme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: caramel,
      brightness: Brightness.dark,
      surface: espresso,
    ).copyWith(
      primary: caramel,
      onPrimary: charcoal,
      secondary: copper,
      onSecondary: charcoal,
      surface: espresso,
      onSurface: cream,
      error: const Color(0xFFE28B7C),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: charcoal,
      canvasColor: charcoal,
      dividerColor: Colors.white10,
      appBarTheme: const AppBarTheme(
        backgroundColor: charcoal,
        foregroundColor: cream,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: cream,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.35,
        ),
      ),
      cardTheme: CardThemeData(
        color: coffee,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.white10),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: caramel,
          foregroundColor: charcoal,
          elevation: 0,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: cream,
          side: const BorderSide(color: copper),
          minimumSize: const Size(0, 46),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: espresso,
        labelStyle: const TextStyle(color: mutedCream),
        hintStyle: const TextStyle(color: mutedCream),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: _inputBorder(Colors.white12),
        enabledBorder: _inputBorder(Colors.white12),
        focusedBorder: _inputBorder(caramel, width: 1.5),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: espresso,
        indicatorColor: copper.withValues(alpha: 0.22),
        elevation: 0,
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: coffee,
        contentTextStyle: const TextStyle(color: cream),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: caramel),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: cream,
          fontSize: 32,
          fontWeight: FontWeight.w800,
          letterSpacing: -1,
        ),
        headlineMedium: TextStyle(
          color: cream,
          fontSize: 25,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.55,
        ),
        titleLarge: TextStyle(
          color: cream,
          fontSize: 19,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: TextStyle(
          color: cream,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(color: cream, fontSize: 14),
        bodyMedium: TextStyle(color: mutedCream, fontSize: 13),
      ),
      iconTheme: const IconThemeData(color: caramel),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: width),
      );

  static OutlineInputBorder _emeraldInputBorder(Color color,
          {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: width),
      );
}

/// Transitional color aliases used only by the redesigned dashboard widgets.
/// Remove these when the remaining screens migrate to the Emerald palette.
abstract final class DashboardPalette {
  static const forest = AppTheme.forest;
  static const emerald = AppTheme.emerald;
  static const emeraldBright = AppTheme.emeraldBright;
  static const orange = AppTheme.orange;
  static const orangeDeep = AppTheme.orangeDeep;
  static const paper = AppTheme.paper;
  static const card = AppTheme.card;
  static const ink = AppTheme.ink;
  static const mutedInk = AppTheme.mutedInk;
  static const softGreen = AppTheme.softGreen;
  static const softOrange = AppTheme.softOrange;
  static const line = AppTheme.line;
}
