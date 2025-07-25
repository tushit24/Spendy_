import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'dart:math' as math;
import 'onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _coinController;
  late Animation<double> _coinRotation;

  @override
  void initState() {
    super.initState();
    _coinController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _coinRotation = Tween<double>(begin: 0, end: 2 * math.pi).animate(
      CurvedAnimation(parent: _coinController, curve: Curves.easeInOut),
    );
    Future.delayed(const Duration(seconds: 2), () {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const OnboardingScreen()),
      );
    });
  }

  @override
  void dispose() {
    _coinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double logoSize = MediaQuery.of(context).size.width * 0.9;
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Extra large centered logo with transparent background
            Image.asset(
              'assets/logo_image.png',
              width: logoSize,
              height: logoSize,
              fit: BoxFit.contain,
            ),
            SizedBox(height: logoSize * 0.10),
            // Animated coin below the logo
            AnimatedBuilder(
              animation: _coinRotation,
              builder: (context, child) {
                return Transform.rotate(
                  angle: _coinRotation.value,
                  child: child,
                );
              },
              child: Icon(
                Icons.monetization_on_rounded,
                size: logoSize * 0.20,
                color: AppTheme.gold,
                shadows: [
                  Shadow(
                    color: AppTheme.yellow.withOpacity(0.5),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
