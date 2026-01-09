import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

class ThemeProvider with ChangeNotifier {
  final Box _box = Hive.box('settings');
  bool _isDarkMode;

  ThemeProvider() : _isDarkMode = Hive.box('settings').get('isDarkMode') ?? false;

  bool get isDarkMode => _isDarkMode;

  ThemeMode get themeMode => _isDarkMode ? ThemeMode.dark : ThemeMode.light;

  void toggleTheme() {
    _isDarkMode = !_isDarkMode;
    _box.put('isDarkMode', _isDarkMode);
    notifyListeners();
  }
}
