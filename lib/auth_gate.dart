import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'services/auth_service.dart';
import 'services/firestore_service.dart';
import 'main_nav_screen.dart';
import 'login_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          return const LoginScreen();
        }

        return FutureBuilder(
          future: FirestoreService.instance.createUserIfNotExists(user),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
               return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            if (snap.hasError) {
              return Scaffold(
                body: Center(
                  child: Text('Error creating user profile: ${snap.error}'),
                ),
              );
            }
            return const MainNavScreen();
          },
        );
      },
    );
  }
}

