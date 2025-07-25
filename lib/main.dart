import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'splash_screen.dart';

void main() {
  runApp(const SpendyApp());
}

class SpendyApp extends StatelessWidget {
  const SpendyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SPENDY',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const SplashScreen(),
    );
  }
}
