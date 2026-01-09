import 'package:flutter/material.dart';
import '../services/lock_service.dart';
import 'set_pin_screen.dart';
import '../app_globals.dart';

class ResetAppLockScreen extends StatefulWidget {
  static const routeName = '/reset-app-lock';
  const ResetAppLockScreen({super.key});

  @override
  State<ResetAppLockScreen> createState() => _ResetAppLockScreenState();
}

class _ResetAppLockScreenState extends State<ResetAppLockScreen> {
  bool _useDeviceLock = false;
  bool _isPinSet = false;
  bool _isLoading = true;
  bool _verifying = false;
  final TextEditingController _currentPinController = TextEditingController();
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final useDevice = await LockService.getUseDeviceLock();
    final isPinSet = await LockService.isPinSet();
    if (!mounted) return;
    setState(() {
      _useDeviceLock = useDevice;
      _isPinSet = isPinSet;
      _isLoading = false;
    });
  }

  Future<void> _verifyWithDeviceLock() async {
    setState(() {
      _verifying = true;
      _errorText = null;
    });

    final ok = await LockService.authenticateWithBiometrics(localizedReason: 'Authenticate to reset your PIN', biometricOnly: false);

    if (!mounted) return;
    if (ok) {
      // navigate via root navigator to avoid context-after-await lint
      rootNavigatorKey.currentState?.pushReplacementNamed(SetPinScreen.routeName, arguments: {'isReset': true});
    } else {
      setState(() {
        _errorText = 'Device authentication failed.';
        _verifying = false;
      });
    }
  }

  Future<void> _verifyWithCurrentPin() async {
    setState(() {
      _verifying = true;
      _errorText = null;
    });

    final storedPin = await LockService.getPin();
    if (!mounted) return;

    if (storedPin == null || storedPin.isEmpty) {
      setState(() {
        _errorText = 'No PIN is configured.';
        _verifying = false;
      });
      return;
    }

    if (_currentPinController.text.trim() == storedPin.trim()) {
      rootNavigatorKey.currentState?.pushReplacementNamed(SetPinScreen.routeName, arguments: {'isReset': true});
    } else {
      setState(() {
        _errorText = 'Incorrect PIN. Try again.';
        _verifying = false;
      });
    }
  }

  @override
  void dispose() {
    _currentPinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        appBar: null,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Reset App Lock')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 8),
          const Text(
            'Reset your app PIN',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (_useDeviceLock) ...[
            const Text('Your device lock is enabled. Use it to verify before resetting PIN.'),
            const SizedBox(height: 12),
            if (_errorText != null) Text(_errorText!, style: const TextStyle(color: Colors.red)),
            ElevatedButton.icon(
              onPressed: _verifying ? null : _verifyWithDeviceLock,
              icon: _verifying ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.lock_open),
              label: Text(_verifying ? 'Verifying...' : 'Authenticate with device lock'),
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 12),
            const Text('Or, if you remember your current PIN, you can verify it below:'),
            const SizedBox(height: 8),
            _pinInputSection(),
          ] else if (_isPinSet) ...[
            const Text('Enter your current PIN to reset it.'),
            const SizedBox(height: 12),
            _pinInputSection(),
          ] else ...[
            const Text('No PIN is currently configured. You can set a new PIN directly.'),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                rootNavigatorKey.currentState?.pushReplacementNamed(SetPinScreen.routeName, arguments: {'isReset': true});
              },
              child: const Text('Set PIN now'),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _pinInputSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(
        controller: _currentPinController,
        keyboardType: TextInputType.number,
        maxLength: 4,
        obscureText: true,
        decoration: InputDecoration(
          labelText: 'Current PIN',
          errorText: _errorText,
          counterText: '',
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 8),
      Row(children: [
        ElevatedButton(
          onPressed: _verifying ? null : _verifyWithCurrentPin,
          child: _verifying ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Verify PIN'),
        ),
        const SizedBox(width: 12),
        if (_useDeviceLock)
          TextButton(
            onPressed: _verifying ? null : _verifyWithDeviceLock,
            child: const Text('Use device lock instead'),
          ),
      ]),
    ]);
  }
}
