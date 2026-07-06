// lib/main.dart
// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'package:edutracker/screens/add_student_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/material.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';

import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'app_globals.dart';
import 'providers/edutrack_provider.dart';
import 'providers/theme_provider.dart';
import 'widgets/bottom_nav_shell.dart';

import 'screens/create_batch_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/history_screen.dart';
import 'screens/due_details_screen.dart';
import 'screens/yearly_history_screen.dart';

import 'screens/app_locking_screen.dart';
import 'screens/set_pin_screen.dart';
import 'screens/auth_lock_screen.dart';
import 'screens/reset_app_lock_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/subscribe_screen.dart';
import 'screens/google_sign_in_screen.dart';

import 'models/student.dart';
import 'models/batch.dart';
import 'models/payment_record.dart';

import 'services/lock_service.dart';
import 'services/ad_manager.dart';
import 'services/firestore_sync_service.dart';
import 'services/notification_service.dart';
import 'services/smart_notification_service.dart';

/// ENTRY POINT
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1) Initialize Firebase early
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Initialize Notification Service
  try {
    await NotificationService.instance.init();
  } catch (e) {
    if (kDebugMode) {
      print('NotificationService init error: $e');
    }
  }

  // 2) Initialize Hive, register adapters and open all essential boxes synchronously
  try {
    await Hive.initFlutter();

    // register adapters — ensure your adapter classes exist and typeIds are unique
    Hive.registerAdapter(StudentAdapter());
    Hive.registerAdapter(BatchAdapter());
    Hive.registerAdapter(PaymentRecordAdapter());

    // open boxes synchronously so providers can rely on them immediately
    await Hive.openBox('settings');
    // typed boxes (use same names as your provider expects)
    await Hive.openBox<Student>('students');
    await Hive.openBox<Batch>('batches');
    await Hive.openBox<PaymentRecord>('payments');
  } catch (e, st) {
    if (kDebugMode) {
      print('Hive init/open (essential) error: $e');
      print(st);
    }
    // continue (we will fallback to SharedPreferences where applicable)
  }

  // 3) Start background initialization for non-blocking work (ads, any other lazy opens)
  _startBackgroundInitialization();

  // 4) Read onboarding pref (prefer Hive, fallback to SharedPreferences)
  bool onboardingPref = false;
  try {
    if (Hive.isBoxOpen('settings')) {
      final box = Hive.box('settings');
      onboardingPref =
          box.get('onboarding_complete', defaultValue: false) as bool? ?? false;
    } else {
      final prefs = await SharedPreferences.getInstance();
      onboardingPref = prefs.getBool('onboarding_complete') ?? false;
    }
  } catch (e) {
    if (kDebugMode) print('Error reading onboarding flag: $e');
  }

  // 5) Run the auth-driven app root
  runApp(AuthRoot(onboardingPref: onboardingPref));
}

/// background init for non-blocking work
void _startBackgroundInitialization() {
  Future.microtask(() async {
    // Ads init
    try {
      if (!kIsWeb) {
        await MobileAds.instance.initialize();
        await AdManager.instance.init();
      }
    } catch (e) {
      if (kDebugMode) print('Ads init error: $e');
    }

    // Other boxes already opened synchronously; if you need additional lazy opens, do here.
    // Example (kept for safety): reopen in background if somehow not open
    try {
      if (!Hive.isBoxOpen('students')) await Hive.openBox<Student>('students');
      if (!Hive.isBoxOpen('batches')) await Hive.openBox<Batch>('batches');
      if (!Hive.isBoxOpen('payments')) {
        await Hive.openBox<PaymentRecord>('payments');
      }
    } catch (e) {
      if (kDebugMode) print('Hive background open error: $e');
    }
  });
}

/// Root widget: top-level providers + single MaterialApp
class AuthRoot extends StatefulWidget {
  final bool onboardingPref;
  const AuthRoot({super.key, required this.onboardingPref});

  @override
  State<AuthRoot> createState() => _AuthRootState();
}

class _AuthRootState extends State<AuthRoot> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SmartNotificationService.instance.initSchedules();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await NotificationService.instance.requestPermissions();
      } catch (e) {
        if (kDebugMode) {
          print('Error requesting notification permissions: $e');
        }
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.detached) {
      SmartNotificationService.instance.scheduleInactiveReminders();
    } else if (state == AppLifecycleState.resumed) {
      SmartNotificationService.instance.cancelInactiveReminders();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => EduTrackProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: Consumer<ThemeProvider>(builder: (context, themeProvider, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'EduTrack',
          scaffoldMessengerKey:
              rootScaffoldMessengerKey, // only place to set global keys
          navigatorKey: rootNavigatorKey,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
            useMaterial3: true,
            fontFamily: 'Montserrat',
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.deepPurple, brightness: Brightness.dark),
            useMaterial3: true,
            fontFamily: 'Montserrat',
          ),
          themeMode: themeProvider.themeMode,
          // initial UI decided by auth + onboarding
          home: StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const _QuickSplash();
              }

              final user = snapshot.data;

              // Handle sign-out: stop listeners when user becomes null
              if (user == null) {
                FirestoreSyncService.instance.stopListeners();
                return const GoogleSignInScreen();
              }

              // Handle sign-in: sync local to firestore and start listeners
              // This logic is placed here to ensure it runs when a user is signed in.
              // Note: This might be called multiple times if the StreamBuilder rebuilds.
              // A more robust solution would involve a StatefulWidget to manage auth state subscriptions and side effects.
              FirestoreSyncService.instance
                  .syncLocalToFirestore(user.uid)
                  .catchError((e) {
                // Log or handle the error appropriately
                if (kDebugMode) {
                  print('Error syncing local to Firestore: $e');
                }
              }).whenComplete(() {
                FirestoreSyncService.instance.startListeners(user.uid);
              });

              // user signed in -> decide onboarding
              bool onboardingComplete = widget.onboardingPref;
              try {
                if (Hive.isBoxOpen('settings')) {
                  final box = Hive.box('settings');
                  onboardingComplete = box.get('onboarding_complete',
                          defaultValue: widget.onboardingPref) as bool? ??
                      widget.onboardingPref;
                }
              } catch (_) {}

              if (!onboardingComplete) {
                return const OnboardingScreen();
              }

              // onboarding done -> show app with splash animation (no extra MaterialApp)
              return const AppWithSplash();
            },
          ),
          routes: {
            '/add-student': (_) => const AddStudentScreen(),
            '/create-batch': (_) => const CreateBatchScreen(),
            '/history': (_) => const HistoryScreen(),
            '/due-details': (_) => const DueDetailsScreen(),
            '/batches': (_) => const BottomNavShell(),
            '/subscribe': (_) => const SubscribeScreen(),
            AppLockingScreen.routeName: (_) => const AppLockingScreen(),
            SetPinScreen.routeName: (_) => const SetPinScreen(),
            ResetAppLockScreen.routeName: (_) => const ResetAppLockScreen(),
            SettingsScreen.routeName: (_) => const SettingsScreen(),
            '/yearly-history': (_) => const YearlyHistoryScreen(),
          },
        );
      }),
    );
  }
}

/// quick small splash while auth/hive determines state
class _QuickSplash extends StatelessWidget {
  const _QuickSplash();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF04123A),
      body: SafeArea(
        child: Center(
            child: Image.asset('assets/New logo Edutracker.jpg', width: 120)),
      ),
    );
  }
}

/// AppWithSplash: shows splash animation then returns main app UI (not a MaterialApp)
class AppWithSplash extends StatefulWidget {
  const AppWithSplash({super.key});

  @override
  State<AppWithSplash> createState() => _AppWithSplashState();
}

class _AppWithSplashState extends State<AppWithSplash>
    with SingleTickerProviderStateMixin {
  bool _revealApp = false;
  late final AnimationController _controller;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _shadowAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));

    _scaleAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.88)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.88, end: 1.22)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 60,
      ),
    ]).animate(_controller);

    _shadowAnim = Tween<double>(begin: 6.0, end: 22.0)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _controller.forward();

    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _revealApp = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_revealApp) {
      return const EduTrackApp();
    }

    // return splash Scaffold directly (NO MaterialApp here)
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF04123A), Color(0xFF062B6D)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Transform.scale(
                  scale: _scaleAnim.value,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 220,
                        height: 220,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(32),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(90),
                              blurRadius: _shadowAnim.value,
                              offset: const Offset(0, 10),
                            ),
                            BoxShadow(
                              color: const Color.fromARGB(255, 1, 140, 158)
                                  .withAlpha(90),
                              blurRadius: 40,
                              spreadRadius: 2,
                            ),
                          ],
                          gradient: const LinearGradient(
                            colors: [
                              Color.fromARGB(255, 255, 255, 255),
                              Color.fromARGB(255, 255, 255, 255),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(32),
                          child: Image.asset(
                            'assets/New logo Edutracker.jpg',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'EDUTRACKER',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'SMART WAY TO TRACK EDUCATION',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// EduTrackApp: actual app content (listening to onboarding flag changes)
class EduTrackApp extends StatefulWidget {
  const EduTrackApp({super.key});

  @override
  State<EduTrackApp> createState() => _EduTrackAppState();
}

class _EduTrackAppState extends State<EduTrackApp> with WidgetsBindingObserver {
  bool _isAppLocked = false;
  bool _isFirstTimeSetupComplete =
      true; // default true because we reach here after onboarding check
  Timer? _lockTimer;
  Box<dynamic>? _settingsBox;
  late final VoidCallback _settingsListener;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // settings listener to react if onboarding flag changes at runtime
    _settingsListener = () {
      if (mounted) {
        final val = _settingsBox?.get('onboarding_complete', defaultValue: true)
                as bool? ??
            true;
        setState(() {
          _isFirstTimeSetupComplete = val;
        });
      }
    };

    if (Hive.isBoxOpen('settings')) {
      _settingsBox = Hive.box('settings');
      try {
        _settingsBox?.listenable(
            keys: ['onboarding_complete']).addListener(_settingsListener);
      } catch (e) {
        if (kDebugMode) print('Could not attach settings listener: $e');
      }
    } else {
      Hive.openBox('settings').then((box) {
        _settingsBox = box;
        try {
          box.listenable(
              keys: ['onboarding_complete']).addListener(_settingsListener);
        } catch (e) {
          if (kDebugMode) {
            print('Could not attach settings listener (late): $e');
          }
        }
      });
    }

    _checkAppLockStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lockTimer?.cancel();
    try {
      _settingsBox?.listenable(
          keys: ['onboarding_complete']).removeListener(_settingsListener);
    } catch (_) {}
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _lockTimer?.cancel();
      _lockTimer = Timer(const Duration(seconds: 8), () async {
        await LockService.setAppLocked(true);
        if (mounted) setState(() => _isAppLocked = true);
      });
    } else if (state == AppLifecycleState.resumed) {
      _lockTimer?.cancel();
      _lockTimer = null;
      _checkAppLockStatus();
    }
  }

  Future<void> _checkAppLockStatus() async {
    final overlayContext = rootNavigatorKey.currentState?.overlay?.context;
    final currentRouteName = overlayContext == null
        ? null
        : ModalRoute.of(overlayContext)?.settings.name;

    if (currentRouteName == SettingsScreen.routeName ||
        currentRouteName == AppLockingScreen.routeName) {
      return;
    }

    final bool isConfigured = await LockService.isConfigured();
    if (!isConfigured) {
      if (mounted) setState(() => _isAppLocked = false);
      return;
    }

    final bool appLockedState = await LockService.isAppLocked();
    final newState = appLockedState && _isFirstTimeSetupComplete;

    if (mounted && _isAppLocked != newState) {
      setState(() {
        _isAppLocked = newState;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // If onboarding is turned off while in app, navigate back to onboarding
    if (!_isFirstTimeSetupComplete) {
      Future.microtask(() {
        if (mounted) {
          Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const OnboardingScreen()));
        }
      });
      return const SizedBox.shrink();
    }

    // Show auth lock screen if required, else main bottom nav
    if (_isAppLocked) {
      return AuthLockScreen(
        // key: UniqueKey(), // Removed to prevent re-initialization loop
        onUnlock: () async {
          await LockService.setAppLocked(false);
          if (mounted) setState(() => _isAppLocked = false);
        },
      );
    }

    return const BottomNavShell();
  }
}
