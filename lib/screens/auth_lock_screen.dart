import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/lock_service.dart';
import '../providers/edutrack_provider.dart';

class AuthLockScreen extends StatefulWidget {
  static const routeName = '/auth-lock-screen';
  final VoidCallback onUnlock;
  const AuthLockScreen({super.key, required this.onUnlock});

  @override
  State<AuthLockScreen> createState() => _AuthLockScreenState();
}

class _AuthLockScreenState extends State<AuthLockScreen> {
  final TextEditingController _pinController = TextEditingController();
  final FocusNode _pinFocusNode = FocusNode();
  bool _useFingerprint = false;
  bool _useDeviceLock = false;
  bool _isPinSet = false;
  String? _errorText;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadLockSettings();
  }

  @override
  void dispose() {
    _pinController.dispose();
    _pinFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadLockSettings() async {
    _useFingerprint = await LockService.getUseFingerprint();
    _useDeviceLock = await LockService.getUseDeviceLock();
    _isPinSet = await LockService.isPinSet();

    if (!mounted) return;
    setState(() {});

    // PIN unlock হলে স্ক্রিন খোলার সাথে সাথে কীবোর্ড ওপেন করানো
    if (_isPinSet && !_useFingerprint && !_useDeviceLock) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _pinFocusNode.requestFocus();
          SystemChannels.textInput.invokeMethod('TextInput.show');
        }
      });
    }

    // Try immediate biometric/device unlock if configured
    if (_useFingerprint) {
      final ok = await LockService.authenticateWithBiometrics(
        localizedReason: 'Please authenticate to unlock the app',
        biometricOnly: true,
      );
      if (ok && mounted) widget.onUnlock();
    } else if (_useDeviceLock) {
      final ok = await LockService.authenticateWithBiometrics(
        localizedReason: 'Please authenticate to unlock the app',
        biometricOnly: false,
      );
      if (ok && mounted) widget.onUnlock();
    }
  }

  Future<void> _verifyPin() async {
    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    final storedPin = await LockService.getPin();

    if (!mounted) return;

    if (storedPin == null || storedPin.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorText = 'No PIN configured. Set a PIN in Settings first.';
      });
      return;
    }

    if (_pinController.text == storedPin) {
      if (mounted) widget.onUnlock();
    } else {
      setState(() {
        _isLoading = false;
        _errorText = 'Incorrect PIN.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<EduTrackProvider>(context).appColor;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Unlock EduTracker'),
        backgroundColor: theme,
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (_useFingerprint)
              Column(children: [
                const Icon(Icons.fingerprint, size: 80),
                const SizedBox(height: 10),
                const Text('Verify with fingerprint'),
                const SizedBox(height: 8),
                ElevatedButton(
                    onPressed: () async {
                      final ok = await LockService.authenticateWithBiometrics(
                          localizedReason: 'Scan fingerprint',
                          biometricOnly: true);
                      if (ok && mounted) widget.onUnlock();
                    },
                    child: const Text('Scan Fingerprint')),
              ])
            else if (_useDeviceLock)
              Column(children: [
                const Icon(Icons.lock_outline, size: 80),
                const SizedBox(height: 10),
                const Text('Verify with device lock'),
                const SizedBox(height: 8),
                ElevatedButton(
                    onPressed: () async {
                      final ok = await LockService.authenticateWithBiometrics(
                          localizedReason: 'Use device lock to unlock',
                          biometricOnly: false);
                      if (ok && mounted) widget.onUnlock();
                    },
                    child: const Text('Unlock with device lock')),
              ])
            else if (_isPinSet)
              Column(children: [
                const Icon(Icons.lock_open, size: 80),
                const SizedBox(height: 10),
                const Text('Enter your 4-digit PIN'),
                const SizedBox(height: 12),
                SizedBox(
                  width: 200,
                  child: TextField(
                    controller: _pinController,
                    focusNode: _pinFocusNode,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    obscureText: true,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      labelText: 'PIN',
                      errorText: _errorText,
                      border: const OutlineInputBorder(),
                      counterText: '',
                    ),
                    onSubmitted: (_) => _verifyPin(),
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                    onPressed: _isLoading ? null : _verifyPin,
                    child: _isLoading
                        ? const CircularProgressIndicator()
                        : const Text('Unlock')),
              ])
            else
              const Text('App lock is not configured.'),
          ]),
        ),
      ),
    );
  }
}
