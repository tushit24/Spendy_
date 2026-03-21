import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'services/auth_service.dart';
import 'services/firestore_service.dart';
import 'main_nav_screen.dart';
import 'login_screen.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  /// Retry trigger — incrementing this forces the StreamBuilder to rebuild
  int _retryCount = 0;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      // Key changes on retry so a fresh stream is created
      key: ValueKey(_retryCount),
      stream: AuthService.instance
          .authStateChanges()
          .timeout(const Duration(seconds: 30)),
      builder: (context, snapshot) {
        // ─── ERROR / TIMEOUT ────────────────────────────────────
        if (snapshot.hasError) {
          return _buildOfflineScreen(error: snapshot.error);
        }

        // ─── LOADING (only while waiting for first auth event) ───
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: AppTheme.background,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Connecting...', style: TextStyle(color: AppTheme.textSecondary)),
                ],
              ),
            ),
          );
        }

        // ─── NOT LOGGED IN ──────────────────────────────────────
        final user = snapshot.data;
        if (user == null) {
          return const LoginScreen();
        }

        // ─── LOGGED IN → Initialize & go to MainNavScreen ───────
        return _InitGate(
          user: user,
          onRetry: _retry,
        );
      },
    );
  }

  void _retry() {
    setState(() {
      _retryCount++;
    });
  }

  bool _isTimeoutError(Object? error) {
    if (error == null) return false;
    return error.toString().contains('TimeoutException');
  }

  Widget _buildOfflineScreen({Object? error}) {
    final isTimeout = _isTimeoutError(error);
    final icon = isTimeout ? Icons.hourglass_top_rounded : Icons.wifi_off;
    final iconColor = isTimeout ? AppTheme.yellow : Colors.grey;
    final message = isTimeout
        ? 'Taking longer than usual'
        : 'Something went wrong';
    final subtitle = isTimeout
        ? 'The server is slow to respond. Please try again.'
        : 'Please check your connection and try again.';

    return _AutoRetryWrapper(
      onRetry: _retry,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 64, color: iconColor),
                const SizedBox(height: 20),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: const TextStyle(color: AppTheme.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try Again'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Separate StatefulWidget for post-auth initialization ────────────────────
// This keeps the FutureBuilder lifecycle clean and independently retryable.
class _InitGate extends StatefulWidget {
  final User user;
  final VoidCallback onRetry;

  const _InitGate({required this.user, required this.onRetry});

  @override
  State<_InitGate> createState() => _InitGateState();
}

class _InitGateState extends State<_InitGate> {
  late Future<void> _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = _initialize();
  }

  Future<void> _initialize() async {
    await FirestoreService.instance
        .createUserIfNotExists(widget.user)
        .timeout(const Duration(seconds: 30));
    await NotificationService()
        .init(widget.user.uid)
        .timeout(const Duration(seconds: 30));
  }

  void _retryInit() {
    setState(() {
      _initFuture = _initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snap) {
        // ─── ERROR / TIMEOUT ────────────────────────────────────
        if (snap.hasError) {
          final isTimeout = snap.error.toString().contains('TimeoutException');
          return _AutoRetryWrapper(
            onRetry: _retryInit,
            child: Scaffold(
              backgroundColor: AppTheme.background,
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isTimeout ? Icons.hourglass_top_rounded : Icons.wifi_off,
                        size: 64,
                        color: isTimeout ? AppTheme.yellow : Colors.grey,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        isTimeout
                            ? 'Taking longer than usual'
                            : 'Something went wrong',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isTimeout
                            ? 'The server is slow to respond. Please try again.'
                            : 'Could not load your profile. Please check your connection.',
                        style: const TextStyle(color: AppTheme.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _retryInit,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try Again'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 32, vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        // ─── LOADING ────────────────────────────────────────────
        if (snap.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: AppTheme.background,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Connecting...', style: TextStyle(color: AppTheme.textSecondary)),
                ],
              ),
            ),
          );
        }

        // ─── SUCCESS → Launch main app ──────────────────────────
        return const MainNavScreen();
      },
    );
  }
}

class _AutoRetryWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback onRetry;
  const _AutoRetryWrapper({required this.child, required this.onRetry});

  @override
  State<_AutoRetryWrapper> createState() => _AutoRetryWrapperState();
}

class _AutoRetryWrapperState extends State<_AutoRetryWrapper> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 2), () {
      if (mounted) widget.onRetry();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
