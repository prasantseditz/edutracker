// lib/screens/dashboard_screen.dart
// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'package:flutter/services.dart';

import 'package:edutracker/screens/google_sign_in_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:page_transition/page_transition.dart';
import '../widgets/payment_warning_dialog.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';

import 'subscribe_screen.dart';
import '../providers/edutrack_provider.dart';
import '../providers/theme_provider.dart';
import '../models/student.dart';
import '../models/payment_record.dart';
import 'batches_screen.dart';
import 'batch_details_screen.dart';
import 'student_details_screen.dart';
import 'app_locking_screen.dart';
import 'report_problem_screen.dart';
import '../app_globals.dart';
// import '../widgets/banner_ad_widget.dart'; // Removed
import '../services/ad_manager.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  late final TextEditingController _searchController;
  late final FocusNode _searchFocus;
  String _searchQuery = '';
  bool _isSearchFocused = false;
  bool _isAdBlockerDialogShowing = false;
  bool _isNoInternetDialogShowing = false;
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;

  // used key from AdManager (keeps parity with AdManager's persistence)
  static const String _rewardTimestampKey = 'reward_watched_at_ms';
  static const Duration _blockDuration = Duration(hours: 12);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initial Check
    _checkConnectivity();
    // Real-time Listener
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen(_updateConnectionStatus);

    _searchController = TextEditingController()..addListener(_onSearchChanged);
    _searchFocus = FocusNode()..addListener(_onFocusChange);

    // Initialize/load ads early (safe to call multiple times)
    try {
      AdManager.instance.init();
    } catch (e) {
      if (kDebugMode) print('AdManager.init error: $e');
    }

    // Check for Ad Blocker
    _checkAdBlocker();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAdBlocker();
      // Also re-check connectivity on resume just in case
      _checkConnectivity();
    }
  }

  Future<void> _checkAdBlocker() async {
    // Small delay to let the app settle
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    if (_isAdBlockerDialogShowing) return;

    final isBlocked = await AdManager.instance.detectAdBlocker();
    if (isBlocked && mounted && !_isAdBlockerDialogShowing) {
      _showAdBlockerDialog();
    }
  }

  void _showAdBlockerDialog() {
    if (_isAdBlockerDialogShowing) return;
    _isAdBlockerDialogShowing = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning, color: Colors.orange),
              SizedBox(width: 8),
              Expanded(child: Text('Ad Blocker Detected')),
            ],
          ),
          content: const Text(
            'It appears you are using an Ad Blocker or a Private DNS (like dns.adguard.com).\n\n'
            'This free app relies on ads to keep running. Please disable your ad blocker or private DNS to continue.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                // Exit App
                try {
                  // We don't set _isAdBlockerDialogShowing = false here because we are exiting.
                  // But just in case exit fails:
                  // _isAdBlockerDialogShowing = false;
                  // actually better to keep it true so it doesn't pop up again before exit
                  Navigator.of(context).pop();
                  SystemNavigator.pop();
                } catch (_) {}
              },
              child:
                  const Text('Exit App', style: TextStyle(color: Colors.red)),
            ),
            ElevatedButton(
              onPressed: () async {
                // Close dialog temporarily
                Navigator.of(context).pop();

                // Show checking loading indicator
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (ctx) =>
                      const Center(child: CircularProgressIndicator()),
                );

                // Re-check
                final stillBlocked = await AdManager.instance.detectAdBlocker();

                if (!mounted) return;
                Navigator.of(context).pop(); // Remove loader

                if (stillBlocked) {
                  // Show blocker dialog again
                  _isAdBlockerDialogShowing =
                      false; // Reset so we can show again
                  _showAdBlockerDialog();
                } else {
                  // Success
                  _isAdBlockerDialogShowing = false;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Thanks! You can now use the app.')),
                  );
                }
              },
              child: const Text('I Disabled It, Retry'),
            ),
          ],
        ),
      ),
    ).then((_) {
      // Just in case it's closed by some other means (unlikely with barrierDismissible: false)
      if (mounted) {
        // We only set false if we are not exiting or retrying immediately in the logic above
        // But since logic above handles it, this is a fallback.
        // However, if we put _isAdBlockerDialogShowing = false here, it might conflict with the recursive call logic in "Retry".
        // Let's rely on the explicit sets in the button handlers.
      }
    });
  }

  Future<void> _checkConnectivity() async {
    final connectivityResult = await (Connectivity().checkConnectivity());
    _updateConnectionStatus(connectivityResult);
  }

  void _updateConnectionStatus(ConnectivityResult result) {
    if (result == ConnectivityResult.none) {
      if (!_isNoInternetDialogShowing && mounted) {
        _showNoInternetDialog();
      }
    } else {
      if (_isNoInternetDialogShowing && mounted) {
        Navigator.of(context).pop();
        _isNoInternetDialogShowing = false;
      }
    }
  }

  void _showNoInternetDialog() {
    _isNoInternetDialogShowing = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('No Internet Connection'),
        content: const Text(
            'Your internet connection appears to be offline. Please enable it to use all features.'),
        actions: [
          TextButton(
            onPressed: () {
              // User acknowledged, but we keep state true so it doesn't pop again immediately
              // unless status changes and comes back.
              // Actually if they click OK, they probably want to use offline mode.
              // But the prompt was "warn" them.
              Navigator.of(context).pop();
              // We set false so if it happens again (flap), it shows again.
              _isNoInternetDialogShowing = false;
            },
            child: const Text('OK'),
          ),
        ],
      ),
    ).then((_) {
      // Fallback
      if (mounted) _isNoInternetDialogShowing = false;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    _searchFocus
      ..removeListener(_onFocusChange)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.trim();
    });
  }

  void _onFocusChange() {
    setState(() {
      _isSearchFocused = _searchFocus.hasFocus;
    });
  }

  // ---------- Helper: show ad per N taps policy ----------
  /// Runs [action] either immediately or after showing interstitial.
  /// Policy: show ad once every 2 taps for the given [key].
  Future<void> _onActionWithAd(String key, VoidCallback action) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final counterKey = 'ad_counter_$key';
      int cnt = prefs.getInt(counterKey) ?? 0;
      cnt++;
      await prefs.setInt(counterKey, cnt);

      // Ask AdManager to show interstitial if allowed (it respects reward-block)
      if (kDebugMode) {
        debugPrint('Dashboard: Attempting to show interstitial ad for $key');
      }
      await AdManager.instance.showInterstitialIfAllowed(onAdComplete: action);
    } catch (e) {
      if (kDebugMode) debugPrint('Dashboard: _onActionWithAd error: $e');
      // fallback to action if anything goes wrong
      try {
        action();
      } catch (actionError) {
        if (kDebugMode) {
          debugPrint('Dashboard: Action execution error: $actionError');
        }
      }
    }
  }

  String _formatAmount(double amount) {
    if (amount == amount.toInt()) {
      return amount.toInt().toString();
    }
    return amount.toString();
  }

  void _navigateToBatchesWithFilter(BuildContext context, int filterIndex) {
    final route = BatchesScreen(initialFilterIndex: filterIndex);
    if (kIsWeb) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => route));
    } else {
      Navigator.of(context).push(
          PageTransition(type: PageTransitionType.rightToLeft, child: route));
    }
  }

  Future<void> _confirmAndTogglePayment(
      Student student, EduTrackProvider provider) async {
    if (!mounted) return;

    if (student.feesPaid) {
      // Toggling back to Due — standard confirmation
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${student.name} - ${student.batchName}'),
          content: const Text('Mark this student as Due for this month?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('No')),
            ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Yes')),
          ],
        ),
      );
      if (confirmed == true) {
        await provider.togglePaymentStatusForMonth(student.id, DateTime.now());
      }
      return;
    }

    // Checking for earlier dues
    final earliestDue = provider.getEarliestUnpaidMonth(student.id);

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => PaymentWarningDialog(
        studentName: student.name,
        targetMonth: DateTime.now(),
        earliestDueMonth: earliestDue,
      ),
    );

    if (result == 'confirm') {
      await provider.togglePaymentStatusForMonth(student.id, DateTime.now());
      if (!mounted) return;
      rootScaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('${student.name} marked as Paid')),
      );
    } else if (result == 'pay_from_earliest' && earliestDue != null) {
      await provider.payDuesInRange(student.id, earliestDue, DateTime.now());
      if (!mounted) return;
      rootScaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
            content: Text(
                'Paid dues from ${DateFormat('MMM yyyy').format(earliestDue)} onwards')),
      );
    }
  }

  // ---------------------------
  // Profile sheet & sign out
  // ---------------------------
  String _initials(String name) {
    if (name.isEmpty) return '';
    final parts = name.trim().split(' ');
    if (parts.length > 1) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  // ---------------------------
  // Profile sheet & sign out
  // ---------------------------
  Future<void> _showProfileMenu() async {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName ??
        (Hive.isBoxOpen('settings')
            ? Hive.box('settings').get('name') ?? 'User'
            : 'User');
    final email = user?.email;
    final photoUrl = user?.photoURL;

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(ctx).pop(),
          child: DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.4,
            maxChildSize: 0.9,
            builder: (_, controller) {
              return GestureDetector(
                onTap:
                    () {}, // Prevent tap from bubbling up to the outer GestureDetector
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                  child: SingleChildScrollView(
                    controller: controller,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // top grabber
                        Center(
                          child: Container(
                            width: 50,
                            height: 6,
                            decoration: BoxDecoration(
                              color:
                                  isDark ? Colors.grey[700] : Colors.grey[300],
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // profile row
                        Row(
                          children: [
                            // avatar
                            CircleAvatar(
                              radius: 36,
                              backgroundColor: isDark
                                  ? Colors.grey[800]
                                  : Colors.grey.shade200,
                              child: ClipOval(
                                child: photoUrl != null
                                    ? Image.network(photoUrl,
                                        width: 72,
                                        height: 72,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) {
                                        return Center(
                                            child: Text(_initials(displayName),
                                                style: TextStyle(
                                                    fontSize: 20,
                                                    fontWeight: FontWeight.w600,
                                                    color: isDark
                                                        ? Colors.white
                                                        : Colors.black)));
                                      })
                                    : Center(
                                        child: Text(_initials(displayName),
                                            style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.w600,
                                                color: isDark
                                                    ? Colors.white
                                                    : Colors.black))),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    displayName,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  if (email != null)
                                    Text(email,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                                color: isDark
                                                    ? Colors.grey[400]
                                                    : Colors.grey[600])),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              icon: Icon(Icons.close,
                                  color: isDark ? Colors.white : Colors.black),
                            ),
                          ],
                        ),

                        const SizedBox(height: 18),

                        // optional account info card
                        Card(
                          margin: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  const Icon(Icons.verified_user_outlined),
                                  const SizedBox(width: 8),
                                  Expanded(
                                      child: Text('Signed in with Google',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium)),
                                ]),
                                const SizedBox(height: 8),
                                Text(
                                    'Manage your account from Google settings if needed.',
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 18),

                        // Sign out button
                        SizedBox(
                          height: 52,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.logout_outlined),
                            label: const Text('Sign out'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Sign Out'),
                                  content: const Text(
                                      'Are you sure you will be sign out and redirected to the sign in screen?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(false),
                                      child: const Text('No'),
                                    ),
                                    ElevatedButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(true),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red,
                                        foregroundColor: Colors.white,
                                      ),
                                      child: const Text('Yes'),
                                    ),
                                  ],
                                ),
                              );

                              if (confirmed == true) {
                                Navigator.of(ctx).pop(); // close sheet
                                await _performSignOut();
                              }
                            },
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Privacy Policy Button
                        SizedBox(
                          height: 52,
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.privacy_tip_outlined),
                            label: const Text('Privacy Policy'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.blue,
                              side: const BorderSide(color: Colors.blue),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () async {
                              const url =
                                  'https://www.freeprivacypolicy.com/live/16bb47cc-f243-4d55-a7cb-e709d6a2b066';
                              if (await canLaunchUrl(Uri.parse(url))) {
                                await launchUrl(Uri.parse(url));
                              } else {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Could not launch privacy policy')));
                                }
                              }
                            },
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Delete Account Button (Play Store Requirement)
                        SizedBox(
                          height: 52,
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.delete_forever),
                            label: const Text('Delete Account'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Delete Account?'),
                                  content: const Text(
                                      'This action is PERMANENT. All your data (students, batches, payments) will be wiped and cannot be recovered.\n\nAre you absolutely sure?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(false),
                                      child: const Text('Cancel'),
                                    ),
                                    ElevatedButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(true),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red,
                                        foregroundColor: Colors.white,
                                      ),
                                      child: const Text('Delete Forever'),
                                    ),
                                  ],
                                ),
                              );

                              if (confirmed == true) {
                                Navigator.of(ctx).pop(); // close sheet
                                try {
                                  final provider =
                                      Provider.of<EduTrackProvider>(context,
                                          listen: false);
                                  await provider.deleteUserAccount();
                                  if (!mounted) return;
                                  // Navigate to login screen
                                  rootNavigatorKey.currentState
                                      ?.pushReplacement(MaterialPageRoute(
                                          builder: (_) =>
                                              const GoogleSignInScreen()));
                                } catch (e) {
                                  if (mounted) {
                                    rootScaffoldMessengerKey.currentState
                                        ?.showSnackBar(SnackBar(
                                            content: Text(
                                                'Failed to delete account: $e. Try signing out and in again.')));
                                  }
                                }
                              }
                            },
                          ),
                        ),

                        const SizedBox(height: 8),

                        // small destructive note
                        Text(
                          'You will be signed out and redirected to the sign-in screen.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.color
                                      ?.withAlpha(72)),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _performSignOut() async {
    try {
      // try GoogleSignIn sign out first (if used)
      try {
        final google = GoogleSignIn();
        if (await google.isSignedIn()) {
          await google.disconnect();
          await google.signOut();
        }
      } catch (e) {
        // don't fail entire sign-out if google sign-out errors; continue to firebase sign-out
        if (kDebugMode) print('GoogleSignIn signOut error: $e');
      }

      await FirebaseAuth.instance.signOut();

      // clear any app-level flags if needed (optional)
      try {
        if (Hive.isBoxOpen('settings')) {
          Hive.box('settings');
          // don't erase onboarding flag here, just optional cleanup
          // box.delete('name'); // uncomment if you want to clear stored name
        }
      } catch (_) {}

      // redirect to GoogleSignInScreen using rootNavigator to ensure top-level route replace
      if (!mounted) return;
      rootNavigatorKey.currentState?.pushReplacement(
          MaterialPageRoute(builder: (_) => const GoogleSignInScreen()));
    } catch (e) {
      if (mounted) {
        rootScaffoldMessengerKey.currentState
            ?.showSnackBar(SnackBar(content: Text('Failed to sign out: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EduTrackProvider>();

    if (provider.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    String name = 'User';
    try {
      if (Hive.isBoxOpen('settings')) {
        final box = Hive.box('settings');
        name = box.get('name') ?? 'User';
      }
    } catch (_) {}

    // fetch firebase user for avatar (do not call heavy work in build, just read)
    final user = FirebaseAuth.instance.currentUser;
    final photoUrl = user?.photoURL;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('EduTrack'),
            if (provider.isPremium) ...[
              const SizedBox(width: 8),
              const Icon(Icons.workspace_premium, color: Colors.amber),
            ],
          ],
        ),
        centerTitle: false,
        elevation: 0,
        actions: [
          // Crown icon placed left of settings
          IconButton(
            icon: const Icon(Icons.workspace_premium),
            tooltip: 'Ad Pause & Subscription',
            onPressed: () => _openAdPauseSheet(context),
          ),

          // Profile icon (new) - shows profile modal sheet on tap
          Padding(
            padding: const EdgeInsets.only(right: 6.0),
            child: IconButton(
              tooltip: 'Profile',
              onPressed: _showProfileMenu,
              icon: photoUrl != null
                  ? CircleAvatar(
                      radius: 16,
                      backgroundImage: NetworkImage(photoUrl),
                      backgroundColor: Colors.transparent,
                    )
                  : CircleAvatar(
                      radius: 16,
                      child: Text(_initials(name),
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
            ),
          ),

          IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () => _showSettingsDialog(context, provider)),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            child: Row(
              children: [
                if (_isSearchFocused || _searchQuery.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () {
                      _searchController.clear();
                      _searchFocus.unfocus();
                      setState(() {
                        _searchQuery = '';
                        _isSearchFocused = false;
                      });
                    },
                  )
                else
                  const SizedBox(width: 48),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12.0),
                      boxShadow: [
                        BoxShadow(
                          color: const Color.fromARGB(255, 0, 97, 207)
                              .withAlpha((255 * 0.04).round()),
                          spreadRadius: 1,
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocus,
                      decoration: InputDecoration(
                        hintText:
                            'Search students or ${provider.batchLabelPlural.toLowerCase()}...',
                        hintStyle: TextStyle(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white60
                              : Colors.black54,
                        ),
                        prefixIcon:
                            const Icon(Icons.search, color: Colors.deepPurple),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.0),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.0),
                          borderSide: const BorderSide(
                              color: Colors.deepPurple, width: 2.0),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 12),
                      ),
                      textInputAction: TextInputAction.search,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
              child: _searchQuery.isEmpty
                  ? _buildDashboard(context, provider, name)
                  : _buildSearchResults(context, provider)),
          const BannerAdWidget(),
        ],
      ),
    );
  }

  Widget _buildDashboard(
      BuildContext context, EduTrackProvider provider, String name) {
    return LayoutBuilder(builder: (context, constraints) {
      final availableWidth = constraints.maxWidth;
      // Padding: 20 left + 20 right = 40
      final contentWidth = availableWidth - 40;

      // Determine columns based on available width
      int crossAxisCount;
      if (availableWidth > 1200) {
        crossAxisCount = 4;
      } else if (availableWidth > 800) {
        crossAxisCount = 3;
      } else {
        crossAxisCount = 2; // Mobile default
      }

      // Calculate gap total: (count - 1) gaps of size 15
      final totalGap = (crossAxisCount - 1) * 15.0;
      final cardWidth = (contentWidth - totalGap) / crossAxisCount;

      return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Welcome back, $name! 👋',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Wrap(
            spacing: 15,
            runSpacing: 15,
            children: [
              // Yearly Summary: Full width on mobile, 2-unit width on Desktop if space allows
              _SummaryCard(
                title: 'Yearly Summary 📅',
                value: 'View Details',
                color: Colors.indigo,
                width: crossAxisCount > 2
                    ? (cardWidth * 2) + 15
                    : contentWidth, // Spans 2 cols on desktop, full on mobile
                onTap: () => _onActionWithAd('yearly_summary',
                    () => Navigator.pushNamed(context, '/yearly-history')),
              ),
              _SummaryCard(
                  title: 'Total Paid (This Month) ✅',
                  value:
                      '${provider.currencySymbol}${_formatAmount(provider.getTotalPaidCurrentMonth())}',
                  color: Colors.green,
                  width: cardWidth,
                  onTap: () => _onActionWithAd('total_paid',
                      () => Navigator.pushNamed(context, '/history'))),
              _SummaryCard(
                  title: 'Total Due (This Month) ⏳',
                  value:
                      '${provider.currencySymbol}${_formatAmount(provider.getTotalDueCurrentMonth())}',
                  color: Colors.orange,
                  width: cardWidth,
                  onTap: () => _onActionWithAd('total_due',
                      () => Navigator.pushNamed(context, '/due-details'))),
              _SummaryCard(
                  title: 'Total Students 🧑‍🎓',
                  value: provider.totalStudents.toString(),
                  color: Colors.deepPurple,
                  width: cardWidth,
                  onTap: () => _onActionWithAd('total_students',
                      () => _navigateToBatchesWithFilter(context, 1))),
              _SummaryCard(
                  title: 'Active ${provider.batchLabelPlural} 📚',
                  value: provider.activeBatches.toString(),
                  color: Colors.blue,
                  width: cardWidth,
                  onTap: () => _onActionWithAd('active_batches',
                      () => _navigateToBatchesWithFilter(context, 0))),
              _SummaryCard(
                  title: 'Add New Student',
                  icon: Icons.person_add,
                  color: Colors.deepPurple,
                  width: cardWidth,
                  onTap: () => _onActionWithAd('add_student',
                      () => Navigator.pushNamed(context, '/add-student'))),
              _SummaryCard(
                  title: 'Add New ${provider.batchLabel}',
                  icon: Icons.group_add,
                  color: Colors.green,
                  width: cardWidth,
                  onTap: () => _onActionWithAd('add_batch',
                      () => Navigator.pushNamed(context, '/create-batch'))),
            ],
          ),
          const SizedBox(height: 25),
        ]),
      );
    });
  }

  Widget _buildSearchResults(BuildContext context, EduTrackProvider provider) {
    final students = provider.searchStudents(_searchQuery);
    final batches = provider.searchBatches(_searchQuery);

    // Sort students by match score first
    final sortedStudents = List<Student>.from(students)
      ..sort((a, b) {
        final sA = _matchScore(a.name, _searchQuery);
        final sB = _matchScore(b.name, _searchQuery);

        if (sA != sB) return sB.compareTo(sA); // High score first
        return a.name.compareTo(b.name); // tie → alphabetical
      });

    // Group students by batch BUT keep order as per sortedStudents (NOT alphabetical)
    final Map<String, List<Student>> studentsByBatch = {};
    for (final s in sortedStudents) {
      studentsByBatch.putIfAbsent(s.batchName, () => []).add(s);
    }

    // ⚠️ Do NOT sort batches alphabetically — keep natural order from match score
    final sortedBatchNames = studentsByBatch.keys.toList();

    // No results
    if (sortedStudents.isEmpty && batches.isEmpty) {
      return Center(
          child: Text('No results found for "$_searchQuery"',
              style: const TextStyle(fontSize: 16)));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ...sortedBatchNames.map((batchName) {
          final batchStudents = studentsByBatch[batchName]!;

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    batchName,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.deepPurple),
                  ),
                  const SizedBox(height: 8),
                  ...batchStudents.map((student) {
                    final payment = provider.payments.firstWhere(
                      (p) =>
                          p.studentId == student.id &&
                          p.month.month == DateTime.now().month &&
                          p.month.year == DateTime.now().year,
                      orElse: () => PaymentRecord(
                          id: '',
                          studentId: student.id,
                          month: DateTime.now(),
                          isPaid: false),
                    );
                    final isPaid = payment.isPaid;

                    return ListTile(
                      title: Text(student.name),
                      subtitle:
                          Text('${provider.subLabel}: ${student.studentClass}'),
                      trailing: ElevatedButton(
                        onPressed: () =>
                            _confirmAndTogglePayment(student, provider),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              isPaid ? Colors.green : Colors.orange,
                        ),
                        child: Text(isPaid ? 'Paid' : 'Due'),
                      ),
                      onTap: () {
                        if (kIsWeb) {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) =>
                                    StudentDetailsScreen(student: student)),
                          );
                        } else {
                          Navigator.of(context).push(PageTransition(
                            type: PageTransitionType.rightToLeft,
                            child: StudentDetailsScreen(student: student),
                          ));
                        }
                      },
                    );
                  }),
                ],
              ),
            ),
          );
        }),

        // Matching Batches Section
        if (batches.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Matching ${provider.batchLabelPlural}',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...batches.map((batch) {
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 5),
              child: ListTile(
                title: Text(batch.name),
                subtitle: Text('${provider.subLabel}: ${batch.studentClass}'),
                onTap: () {
                  if (kIsWeb) {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => BatchDetailsScreen(batch: batch)));
                  } else {
                    Navigator.of(context).push(PageTransition(
                      type: PageTransitionType.rightToLeft,
                      child: BatchDetailsScreen(batch: batch),
                    ));
                  }
                },
              ),
            );
          }),
        ],
      ],
    );
  }

  int _matchScore(String name, String query) {
    final n = name.toLowerCase();
    final q = query.toLowerCase();
    if (n == q) return 100;
    if (n.startsWith(q)) return 80;
    if (n.contains(q)) return 50;
    return 0;
  }

  // ---------------------------
  // Settings dialog (existing)
  // ---------------------------
  void _showSettingsDialog(BuildContext context, EduTrackProvider provider) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Settings'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            SwitchListTile(
              title: const Text('Dark Mode'),
              value: themeProvider.isDarkMode,
              onChanged: (value) {
                themeProvider.toggleTheme();
                Navigator.of(dialogContext).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.lock),
              title: const Text("App Locking"),
              subtitle: const Text("Enable PIN or fingerprint"),
              onTap: () {
                Navigator.of(dialogContext).pop();
                Future.microtask(() {
                  rootNavigatorKey.currentState?.push(MaterialPageRoute(
                      builder: (_) => const AppLockingScreen()));
                });
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.currency_exchange),
              title: const Text('Currency'),
              subtitle: Text(
                  'Current: ${provider.currencySymbol == '₹' ? 'INR (₹)' : 'USD (\$)'}'),
              trailing: DropdownButton<String>(
                value: provider.currencySymbol,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: '₹', child: Text('INR (₹)')),
                  DropdownMenuItem(value: '\$', child: Text('USD (\$)')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    provider.setCurrency(value);
                    Navigator.of(dialogContext).pop();
                  }
                },
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.bug_report_outlined),
              title: const Text('Report a problem'),
              subtitle: const Text('Send issue details to developer'),
              onTap: () {
                Navigator.of(dialogContext).pop();
                Future.microtask(() {
                  rootNavigatorKey.currentState?.push(MaterialPageRoute(
                      builder: (_) => const ReportProblemScreen()));
                });
              },
            ),
          ]),
        );
      },
    );
  }

  // ---------------------------
  // Ad Pause & Subscription sheet
  // ---------------------------
  Future<void> _openAdPauseSheet(BuildContext context) async {
    // read reward-timestamp to compute remaining time (if any)
    final prefs = await SharedPreferences.getInstance();
    final int? ts = prefs.getInt(_rewardTimestampKey);
    DateTime? watchedAt =
        ts == null ? null : DateTime.fromMillisecondsSinceEpoch(ts);

    bool rewardActive = false;
    Duration remaining = Duration.zero;
    if (watchedAt != null) {
      final diff = DateTime.now().difference(watchedAt);
      if (diff < _blockDuration) {
        rewardActive = true;
        remaining = _blockDuration - diff;
      }
    }
    bool intervalExtended = prefs.getBool('ad_interval_extended') ?? false;

    // show modal bottom sheet with stateful builder
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        bool isLoading = false;
        bool isExtendLoading = false;
        bool used = rewardActive;
        bool extended = intervalExtended;

        String prettyDuration(Duration d) {
          final hours = d.inHours;
          final minutes = d.inMinutes.remainder(60);
          if (hours > 0) return '${hours}h ${minutes}m';
          return '${minutes}m';
        }

        return StatefulBuilder(builder: (context, setStateSheet) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 18),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                const Icon(Icons.workspace_premium,
                    size: 28, color: Colors.deepPurple),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Ad Pause & Subscription',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(sheetCtx).pop()),
              ]),
              const SizedBox(height: 12),
              // Subscribe card
              Card(
                child: ListTile(
                  leading: const Icon(Icons.star_border),
                  title: const Text('Subscribe Now'),
                  subtitle: const Text(
                      'Remove ads permanently and get premium features.'),
                  trailing: ElevatedButton(
                    onPressed: () {
                      Navigator.of(sheetCtx).pop();
                      // open SubscribeScreen (use PageTransition on mobile for consistent UX)
                      Future.microtask(() {
                        if (kIsWeb) {
                          Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => const SubscribeScreen()));
                        } else {
                          Navigator.of(context).push(PageTransition(
                            type: PageTransitionType.rightToLeft,
                            child: const SubscribeScreen(),
                          ));
                        }
                      });
                    },
                    child: const Text('Subscribe'),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Watch & Pause card
              Card(
                child: ListTile(
                  leading: const Icon(Icons.play_circle_outline),
                  title: const Text(
                      'Watch an Ad — Pause Interstitials for 12 hours'),
                  subtitle: used
                      ? Text(
                          'Already used. Available in ${prettyDuration(remaining)}')
                      : const Text(
                          'Watch one ad now; no interstitials for the next 12 hours.'),
                  trailing: isLoading
                      ? SizedBox(
                          width: 96,
                          child: Center(
                            child: SizedBox(
                                height: 20,
                                width: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)),
                          ),
                        )
                      : ElevatedButton(
                          onPressed: used
                              ? null
                              : () async {
                                  setStateSheet(() => isLoading = true);
                                  // show rewarded ad via AdManager
                                  AdManager.instance.showRewardedAd(
                                    context: context,
                                    onUserEarnedReward: (reward) async {
                                      // reward granted -> mark watched (AdManager also marks internally in its implementation)
                                      // but to be safe, call markRewardWatched() if available
                                      await AdManager.instance
                                          .markRewardWatched();
                                      // update UI
                                      final prefs =
                                          await SharedPreferences.getInstance();
                                      final int? ts =
                                          prefs.getInt(_rewardTimestampKey);
                                      DateTime? watchedAtLocal = ts == null
                                          ? null
                                          : DateTime.fromMillisecondsSinceEpoch(
                                              ts);
                                      Duration newRemaining = Duration.zero;
                                      bool nowUsed = false;
                                      if (watchedAtLocal != null) {
                                        final diff = DateTime.now()
                                            .difference(watchedAtLocal);
                                        if (diff < _blockDuration) {
                                          nowUsed = true;
                                          newRemaining = _blockDuration - diff;
                                        }
                                      }
                                      setStateSheet(() {
                                        isLoading = false;
                                        used = nowUsed;
                                        remaining = newRemaining;
                                      });
                                      if (mounted) {
                                        Navigator.of(sheetCtx).pop();
                                        rootScaffoldMessengerKey.currentState
                                            ?.showSnackBar(
                                          const SnackBar(
                                              content: Text(
                                                  'Ads paused for the next 12 hours.')),
                                        );
                                      }
                                    },
                                    onAdClosed: () {
                                      // if closed without reward, just stop loading spinner
                                      setStateSheet(() => isLoading = false);
                                    },
                                    onFailedToLoad: (err) {
                                      setStateSheet(() => isLoading = false);
                                      rootScaffoldMessengerKey.currentState
                                          ?.showSnackBar(
                                        SnackBar(
                                            content: Text(
                                                'Ad failed to load: ${err.message}')),
                                      );
                                    },
                                  );
                                },
                          child: const Text('Watch & Pause'),
                        ),
                ),
              ),
              const SizedBox(height: 10),
              // Extend Intervals card
              Card(
                child: ListTile(
                  leading: const Icon(Icons.timer),
                  title: const Text('Watch an Ad — Extend Ad Intervals'),
                  subtitle: extended
                      ? const Text('Already Activated. Ads now appear less frequently.')
                      : const Text('Watch one ad to permanently extend the interval between ads.'),
                  trailing: isExtendLoading
                      ? SizedBox(
                          width: 96,
                          child: Center(
                            child: SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2)),
                          ),
                        )
                      : ElevatedButton(
                          onPressed: extended
                              ? null
                              : () async {
                                  setStateSheet(() => isExtendLoading = true);
                                  AdManager.instance.showRewardedAd(
                                    context: context,
                                    onUserEarnedReward: (reward) async {
                                      final prefs = await SharedPreferences.getInstance();
                                      await prefs.setBool('ad_interval_extended', true);
                                      setStateSheet(() {
                                        isExtendLoading = false;
                                        extended = true;
                                      });
                                      if (mounted) {
                                        Navigator.of(sheetCtx).pop();
                                        rootScaffoldMessengerKey.currentState?.showSnackBar(
                                          const SnackBar(
                                              content: Text('Ad intervals have been permanently extended!')),
                                        );
                                      }
                                    },
                                    onAdClosed: () {
                                      setStateSheet(() => isExtendLoading = false);
                                    },
                                    onFailedToLoad: (err) {
                                      setStateSheet(() => isExtendLoading = false);
                                      rootScaffoldMessengerKey.currentState?.showSnackBar(
                                        SnackBar(content: Text('Ad failed to load: ${err.message}')),
                                      );
                                    },
                                  );
                                },
                          child: const Text('Extend'),
                        ),
                ),
              ),
              const SizedBox(height: 12),
            ]),
          );
        });
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String? value;
  final IconData? icon;
  final Color color;
  final VoidCallback? onTap;
  final double? width;

  const _SummaryCard(
      {required this.title,
      this.value,
      this.icon,
      required this.color,
      this.onTap,
      this.width})
      : assert(value != null || icon != null);

  @override
  Widget build(BuildContext context) {
    final cardWidth =
        width ?? (MediaQuery.of(context).size.width - 40 - 15) / 2;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: cardWidth,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: color.withAlpha((255 * 0.1).round()),
          borderRadius: BorderRadius.circular(15),
          border:
              Border.all(color: color.withAlpha((255 * 0.3).round()), width: 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: TextStyle(
                  fontSize: 15,
                  color: color.withAlpha((255 * 0.8).round()),
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 10),
          if (icon != null)
            Icon(icon, size: 48, color: color)
          else
            Text(value ?? '',
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(color: color, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }
}
