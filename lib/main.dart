import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/auth_gate.dart';

const Color espresso = Color(0xFF171210);
const Color coffee = Color(0xFF241B17);
const Color coffeeCard = Color(0xFF30231D);
const Color caramel = Color(0xFFE5A365);
const Color copper = Color(0xFFC7794D);
const Color cream = Color(0xFFF5E9DD);
const Color mutedCream = Color(0xFFBDA99A);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const BrewVerseApp());
}

class BrewVerseApp extends StatelessWidget {
  const BrewVerseApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: caramel,
      brightness: Brightness.dark,
      surface: coffee,
    );

    return MaterialApp(
      title: 'BrewVerse Cafe Manager',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: espresso,
        canvasColor: espresso,
        dividerColor: Colors.white12,

        appBarTheme: const AppBarTheme(
          backgroundColor: espresso,
          foregroundColor: cream,
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
          titleTextStyle: TextStyle(
            color: cream,
            fontSize: 21,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),

        cardTheme: CardThemeData(
          color: coffeeCard,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(
              color: Colors.white10,
            ),
          ),
        ),

        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: caramel,
            foregroundColor: espresso,
            elevation: 0,
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 14,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
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
          fillColor: coffee,
          labelStyle: const TextStyle(color: mutedCream),
          hintStyle: const TextStyle(color: mutedCream),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 15,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.white12),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.white12),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: caramel,
              width: 1.5,
            ),
          ),
        ),

        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: coffee,
          indicatorColor: copper.withValues(alpha: 0.22),
          elevation: 0,
          labelTextStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),

        snackBarTheme: SnackBarThemeData(
          backgroundColor: coffeeCard,
          contentTextStyle: const TextStyle(color: cream),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),

        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: caramel,
        ),

        textTheme: const TextTheme(
          headlineLarge: TextStyle(
            color: cream,
            fontSize: 30,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
          ),
          headlineMedium: TextStyle(
            color: cream,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
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
          bodyLarge: TextStyle(
            color: cream,
            fontSize: 14,
          ),
          bodyMedium: TextStyle(
            color: mutedCream,
            fontSize: 13,
          ),
        ),

        iconTheme: const IconThemeData(color: caramel),
      ),
      home: const AuthGate(),
    );
  }
}