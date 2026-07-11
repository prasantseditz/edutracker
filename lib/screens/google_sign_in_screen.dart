import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/google_auth_service.dart';

// IMPORT your Dashboard screen here — adjust the path as needed:
// import '../screens/dashboard_screen.dart';
import '../screens/dashboard_screen.dart'; // <-- change path if necessary
import '../screens/onboarding_screen.dart';

/// Modern Google Sign-In screen for EduTrack
class GoogleSignInScreen extends StatefulWidget {
  const GoogleSignInScreen({super.key});

  @override
  State<GoogleSignInScreen> createState() => _GoogleSignInScreenState();
}

class _GoogleSignInScreenState extends State<GoogleSignInScreen> {
  final FirebaseServices _authService = FirebaseServices();
  bool _loading = false;
  String? _error;

  // New: prompt visibility when user tries to navigate but not signed in
  bool _showSignInPrompt = false;
  Timer? _promptTimer;

  Future<void> _handleSignIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final success = await _authService.signInWithGoogle();
      if (!success) {
        setState(() {
          _error = 'Sign in cancelled or failed.';
        });
      } else {
        // If sign-in succeeded, do nothing. The root Consumer handles the screen change.
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleSignOut() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _authService.googleSignOut();
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // New: back/arrow button behavior
  void _onArrowPressed(User? user) {
    if (user == null) {
      // Not signed in -> show persistent line/prompt (for a few seconds)
      setState(() {
        _showSignInPrompt = true;
      });
      _promptTimer?.cancel();
      _promptTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _showSignInPrompt = false);
      });

      // Also show SnackBar briefly for extra feedback
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('First sign in to Google.'),
          duration: Duration(milliseconds: 1500),
        ),
      );
    } else {
      // Signed in -> do nothing, root Consumer handles the screen change.
    }
  }

  @override
  void dispose() {
    _promptTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Sign in with Google'),
        elevation: 0,
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        leading: StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, snapshot) {
            final user = snapshot.data;
            return IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => _onArrowPressed(user),
            );
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Card with illustration / logo
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        theme.colorScheme.primary
                            .withAlpha(36), // 0.14 * 255 = 35.7 -> 36
                        theme.colorScheme.secondary
                            .withAlpha(15), // 0.06 * 255 = 15.3 -> 15
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color.fromARGB(181, 10, 10, 10)
                            .withAlpha(15), // 0.06 * 255 = 15.3 -> 15
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: SizedBox(
                          width: 120,
                          height: 120,
                          child: Image.asset(
                            'assets/New logo Edutracker.jpg',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Welcome to EduTrack',
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Sign in to sync your batches & fees across devices',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.textTheme.bodySmall?.color
                                ?.withAlpha(205)), // 0.8 * 255 = 204
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // Auth state display
                StreamBuilder<User?>(
                  stream: FirebaseAuth.instance.authStateChanges(),
                  builder: (context, snapshot) {
                    final user = snapshot.data;

                    if (_loading) {
                      return const CircularProgressIndicator();
                    }

                    if (user != null) {
                      // Signed in UI
                      return Column(
                        children: [
                          CircleAvatar(
                            radius: 40,
                            backgroundImage: user.photoURL != null
                                ? NetworkImage(user.photoURL!)
                                : null,
                            child: user.photoURL == null
                                ? const Icon(Icons.person, size: 40)
                                : null,
                          ),
                          const SizedBox(height: 12),
                          Text(user.displayName ?? user.email ?? 'User',
                              style: theme.textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text(user.email ?? '',
                              style: theme.textTheme.bodySmall),
                          const SizedBox(height: 18),

                          // Sign out button
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _handleSignOut,
                              icon: const Icon(Icons.logout),
                              label: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 14.0),
                                child: Text('Sign out'),
                              ),
                              style: ElevatedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      );
                    }

                    // Not signed in UI — show Google sign in button
                    return Column(
                      children: [
                        Text('Continue with your Google account',
                            style: theme.textTheme.bodyLarge),
                        const SizedBox(height: 14),

                        // Modern Google button
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: _handleSignIn,
                            style: OutlinedButton.styleFrom(
                              backgroundColor: theme.brightness ==
                                      Brightness.light
                                  ? const Color.fromARGB(255, 248, 255, 246)
                                  : theme.colorScheme.surfaceContainerHighest,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12, horizontal: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.max,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: Image.asset(
                                    'assets/google_logo.png',
                                    fit: BoxFit.contain,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            const Icon(Icons.g_mobiledata,
                                                size: 26),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text('Sign in with Google',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: theme.colorScheme.onSurface,
                                    )),
                              ],
                            ),
                          ),
                        ),

                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(_error!,
                              style: const TextStyle(color: Colors.red)),
                        ],
                      ],
                    );
                  },
                ),

                const SizedBox(height: 18),

                // Small helper note
                Text(
                  'Your data will be synced to your Firebase account. You can always sign out from settings.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),

                if (_showSignInPrompt) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 12),
                    decoration: BoxDecoration(
                      color:
                          Colors.red.withAlpha(15), // 0.06 * 255 = 15.3 -> 15
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.red
                              .withAlpha(36)), // 0.14 * 255 = 35.7 -> 36
                    ),
                    child: const Text(
                      'First sign in to Google to continue.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
