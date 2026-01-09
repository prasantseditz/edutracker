// lib/services/lock_service.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';

class LockService {
  static const _secureStorage = FlutterSecureStorage();
  static const _pinKey = 'app_pin';
  static const _useDeviceLockKey = 'useDeviceLock';
  static const _useFingerprintKey = 'useFingerprint';
  static const _isPinSetKey = 'isPinSet';
  static const _appLockedKey = 'appLocked';

  static Future<void> setPin(String pin) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pinKey, pin);
      await prefs.setBool(_isPinSetKey, true);
      await prefs.setBool(_useDeviceLockKey, false);
    } else {
      await _secureStorage.write(key: _pinKey, value: pin);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_isPinSetKey, true);
      await prefs.setBool(_useDeviceLockKey, false);
    }
  }

  static Future<String?> getPin() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_pinKey);
    } else {
      try {
        return await _secureStorage.read(key: _pinKey);
      } catch (_) {
        final prefs = await SharedPreferences.getInstance();
        return prefs.getString(_pinKey);
      }
    }
  }

  static Future<void> deletePin() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pinKey);
      await prefs.setBool(_isPinSetKey, false);
    } else {
      await _secureStorage.delete(key: _pinKey);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_isPinSetKey, false);
    }
  }

  static Future<bool> isPinSet() async {
    final prefs = await SharedPreferences.getInstance();
    final flag = prefs.getBool(_isPinSetKey);
    if (flag != null) return flag;

    if (kIsWeb) {
      return prefs.containsKey(_pinKey);
    } else {
      try {
        final s = await _secureStorage.read(key: _pinKey);
        if (s != null && s.isNotEmpty) return true;
      } catch (_) {}
      return prefs.containsKey(_pinKey);
    }
  }

  static Future<void> setUseDeviceLock(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    if (kIsWeb && value) {
      await prefs.setBool(_useDeviceLockKey, false);
      return;
    }
    await prefs.setBool(_useDeviceLockKey, value);
    if (value) {
      await deletePin();
    }
  }

  static Future<bool> getUseDeviceLock() async {
    if (kIsWeb) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_useDeviceLockKey) ?? false;
  }

  static Future<void> setUseFingerprint(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    if (kIsWeb && value) {
      await prefs.setBool(_useFingerprintKey, false);
      return;
    }
    await prefs.setBool(_useFingerprintKey, value);
  }

  static Future<bool> getUseFingerprint() async {
    if (kIsWeb) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_useFingerprintKey) ?? false;
  }

  static Future<bool> canCheckBiometrics() async {
    if (kIsWeb) return false;
    final LocalAuthentication auth = LocalAuthentication();
    try {
      return await auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticateWithBiometrics({
    required String localizedReason,
    bool biometricOnly = true,
  }) async {
    if (kIsWeb) return false;
    final LocalAuthentication auth = LocalAuthentication();
    bool canCheck = false;
    try {
      canCheck = await auth.canCheckBiometrics;
    } catch (_) {
      canCheck = false;
    }
    if (canCheck) {
      try {
        return await auth.authenticate(
          localizedReason: localizedReason,
          options: AuthenticationOptions(stickyAuth: true, biometricOnly: biometricOnly),
        );
      } catch (_) {
        return false;
      }
    }
    // If no biometrics, try device credential if biometricOnly==false
    if (!biometricOnly) {
      try {
        return await auth.authenticate(
          localizedReason: localizedReason,
          options: const AuthenticationOptions(stickyAuth: true, biometricOnly: false),
        );
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  static Future<void> setAppLocked(bool locked) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_appLockedKey, locked);
  }

  static Future<bool> isAppLocked() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_appLockedKey) ?? false;
  }

  static Future<bool> isConfigured() async {
    if (kIsWeb) {
      final pinSet = await isPinSet();
      return pinSet;
    }
    final bool pinAlreadySet = await isPinSet();
    final bool useDeviceLock = await getUseDeviceLock();
    final bool useFingerprint = await getUseFingerprint();
    return pinAlreadySet || useDeviceLock || useFingerprint;
  }
}
