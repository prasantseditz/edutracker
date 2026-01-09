import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../services/ad_manager.dart';
import '../services/lock_service.dart';
import '../app_globals.dart';
import 'set_pin_screen.dart';

class AppLockingScreen extends StatefulWidget {
  static const routeName = '/app-locking-screen';
  const AppLockingScreen({super.key});

  @override
  State<AppLockingScreen> createState() => _AppLockingScreenState();
}

class _AppLockingScreenState extends State<AppLockingScreen> {
  bool _useDeviceLock = false;
  bool _isPinSet = false;
  bool _loading = true;

  final LocalAuthentication _localAuth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final device = await LockService.getUseDeviceLock();
    final isPin = await LockService.isPinSet();
    if (!mounted) return;
    setState(() {
      _useDeviceLock = device;
      _isPinSet = isPin;
      _loading = false;
    });
  }

  Future<void> _setUseDeviceLock(bool value) async {
    final messenger = rootScaffoldMessengerKey.currentState;
    if (value) {
      bool ok = false;
      try {
        ok = await _localAuth.authenticate(
          localizedReason: 'Authenticate to enable device lock for app',
          options: const AuthenticationOptions(
            stickyAuth: true,
            biometricOnly: false,
          ),
        );
      } catch (e) {
        messenger?.showSnackBar(
            SnackBar(content: Text('Device authentication error: $e')));
        return;
      }

      if (!ok) {
        messenger?.showSnackBar(const SnackBar(
            content: Text('Authentication failed. Device lock not enabled.')));
        return;
      }

      await LockService.setUseDeviceLock(true);
      await LockService.deletePin(); // single source
      if (!mounted) return;
      setState(() {
        _useDeviceLock = true;
        _isPinSet = false;
      });
      messenger?.showSnackBar(
          const SnackBar(content: Text('Device lock enabled. PIN cleared.')));
    } else {
      await LockService.setUseDeviceLock(false);
      if (!mounted) return;
      setState(() {
        _useDeviceLock = false;
      });
      messenger?.showSnackBar(
          const SnackBar(content: Text('Device lock disabled.')));
    }
  }

  Future<void> _onSetPinTapped() async {
    final nav = rootNavigatorKey.currentState;
    final result = await nav
        ?.pushNamed(SetPinScreen.routeName, arguments: {'isReset': false});
    if (result == true && mounted) {
      final isPin = await LockService.isPinSet();
      if (!mounted) return;
      setState(() {
        _isPinSet = isPin;
        if (_isPinSet) _useDeviceLock = false;
      });
    }
  }

  Future<void> _onResetPinTapped() async {
    final nav = rootNavigatorKey.currentState;
    final messenger = rootScaffoldMessengerKey.currentState;

    final selected = await showModalBottomSheet<String>(
      context: rootNavigatorKey.currentContext!,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.fingerprint),
                title: const Text('Create new PIN'),
                subtitle: const Text('Set a new 4-digit PIN for the app'),
                onTap: () => Navigator.of(ctx).pop('create'),
              ),
              ListTile(
                leading: const Icon(Icons.lock_open),
                title: const Text('Turn off app lock'),
                subtitle: const Text('Disable PIN/device lock for this app'),
                onTap: () => Navigator.of(ctx).pop('turn_off'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (selected == null) return;

    if (selected == 'create') {
      final routeResult = await nav
          ?.pushNamed(SetPinScreen.routeName, arguments: {'isReset': true});
      if (routeResult == true && mounted) {
        await _loadSettings();
      }
    } else if (selected == 'turn_off') {
      await LockService.setUseDeviceLock(false);
      await LockService.deletePin();
      await LockService.setAppLocked(false);
      if (!mounted) return;
      await _loadSettings();
      messenger
          ?.showSnackBar(const SnackBar(content: Text('App lock turned off')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('App Locking')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('App Locking')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8.0),
              children: [
                SwitchListTile(
                  title: const Text(
                      'Use device screen lock (PIN/Pattern/Passcode)'),
                  subtitle: const Text(
                      'Use the existing device screen lock to unlock the app'),
                  value: _useDeviceLock,
                  onChanged: (v) => _setUseDeviceLock(v),
                ),
                ListTile(
                  title: const Text('Create a separate 4-digit PIN'),
                  subtitle: _isPinSet
                      ? const Text('PIN is set')
                      : const Text('No PIN set'),
                  trailing: _isPinSet
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : null,
                  onTap: _onSetPinTapped,
                ),
                if (_isPinSet || _useDeviceLock)
                  ListTile(
                    title: const Text('Reset App Lock'),
                    trailing: const Icon(Icons.refresh),
                    onTap: _onResetPinTapped,
                  ),
                const SizedBox(height: 20),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    'Notes:\n• Enabling device lock will clear any existing custom PIN (to avoid two conflicting unlocks).\n• If you prefer a separate PIN, set it using "Create a separate 4-digit PIN".',
                    style: TextStyle(
                        fontSize: 13, color: Color.fromARGB(221, 247, 88, 88)),
                  ),
                ),
              ],
            ),
          ),

          // ✅ Banner Ad widget at bottom
          const BannerAdWidget(),
        ],
      ),
    );
  }
}
