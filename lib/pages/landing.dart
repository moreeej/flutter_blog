
import 'package:blog/services/auth_service.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const LandingPage());
}

class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Landing Page',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const LandingScreen(),
    );
  }
}

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  void _logCurrentUserSession() {
    final session = currentUserSession;

    if (session == null) {
      debugPrint('currentUserSession: null');
      return;
    }

    final id = session['id']?.toString() ?? 'N/A';
    final email = session['email']?.toString() ?? 'N/A';
    final username = session['username']?.toString() ?? 'N/A';
    final profilePic = session['profile_pic']?.toString() ?? 'N/A';

    debugPrint(
      'currentUserSession -> id: $id, email: $email, username: $username, profile_pic: $profilePic',
    );
  }

  @override
  Widget build(BuildContext context) {
    _logCurrentUserSession();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Landing Page'),
      ),
      body: const Center(
        child: Text('Welcome to the landing page'),
      ),
    );
  }
}