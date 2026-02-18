import 'package:flutter/material.dart';

class AppTheme {
  // Logo-derived poppy colors
  static const Color blue = Color(0xFF2DA6DF);
  static const Color red = Color(0xFFE94B35);
  static const Color yellow = Color(0xFFF7C948);
  static const Color green = Color(0xFF4CB944);
  static const Color gold = Color(0xFFFFD700);

  // Dark theme base
  static const Color background = Color(0xFF111217);
  static const Color card = Color(0xFF1A1B22);
  static const Color textPrimary = Color(0xFFF5F6FA);
  static const Color textSecondary = Color(0xFFB0B3C6);

  // Gradients
  static const Gradient logoGradient = LinearGradient(
    colors: [blue, red, yellow, green],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: background,
    cardColor: card,
    primaryColor: blue,
    colorScheme: ColorScheme.dark(
      primary: blue,
      secondary: yellow,
      surface: card,
      error: red,
      onPrimary: textPrimary,
      onSecondary: textPrimary,
      onSurface: textPrimary,
      onError: textPrimary,
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: textPrimary,
      ),
      headlineMedium: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: textPrimary,
      ),
      bodyLarge: TextStyle(fontSize: 18, color: textPrimary),
      bodyMedium: TextStyle(fontSize: 16, color: textSecondary),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: blue,
        foregroundColor: textPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.bold),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: yellow,
        side: const BorderSide(color: yellow),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      labelStyle: TextStyle(color: textSecondary),
      hintStyle: TextStyle(color: textSecondary),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: background,
      elevation: 0,
      iconTheme: IconThemeData(color: yellow),
      titleTextStyle: TextStyle(
        color: textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    ),
    iconTheme: const IconThemeData(color: yellow),
  );
}
