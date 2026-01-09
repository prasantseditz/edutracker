import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_nav_bar/google_nav_bar.dart';
import '../screens/dashboard_screen.dart';
import '../screens/add_new_screen.dart';
import '../screens/history_screen.dart';
import '../widgets/confirmation_dialog.dart';

import 'web_layout_shell.dart';

class BottomNavShell extends StatefulWidget {
  const BottomNavShell({super.key});

  @override
  State<BottomNavShell> createState() => _BottomNavShellState();
}

class _BottomNavShellState extends State<BottomNavShell> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const DashboardScreen(),
    const AddNewScreen(),
    const HistoryScreen(),
  ];

  Future<void> _handlePop(bool didPop) async {
    if (didPop) return;

    if (_selectedIndex != 0) {
      // If not on Dashboard, go to Dashboard
      setState(() {
        _selectedIndex = 0;
      });
      return;
    }

    // If on Dashboard, show exit confirmation
    final shouldExit = await showConfirmationDialog(
      context,
      'Are you sure you want to exit the app?',
      confirmText: 'Exit',
      cancelText: 'Cancel',
      isDestructive: true,
    );

    if (shouldExit == true) {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Responsive Check: If width > 800, use Web Layout
    if (MediaQuery.of(context).size.width > 800) {
      return const WebLayoutShell();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) => _handlePop(didPop),
      child: Scaffold(
        body: IndexedStack(
          index: _selectedIndex,
          children: _screens,
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Colors.purpleAccent,
                    Colors.deepPurple,
                    Colors.blueAccent
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(2.0), // Gradient border width
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12.0, vertical: 12),
                    child: Builder(builder: (context) {
                      final Shader linearGradient = const LinearGradient(
                        colors: [Colors.purpleAccent, Colors.blueAccent],
                      ).createShader(
                          const Rect.fromLTWH(0.0, 0.0, 200.0, 70.0));

                      return GNav(
                        rippleColor:
                            isDark ? Colors.grey[800]! : Colors.grey[300]!,
                        hoverColor:
                            isDark ? Colors.grey[700]! : Colors.grey[100]!,
                        gap: 8,
                        activeColor: Colors.blueAccent, // Fallback
                        iconSize: 24,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        duration: const Duration(milliseconds: 400),
                        tabBackgroundColor: isDark
                            ? Colors.deepPurple.withValues(alpha: 0.2)
                            : Colors.deepPurpleAccent.withValues(alpha: 0.1),
                        color: isDark ? Colors.grey[400] : Colors.black,
                        tabs: [
                          GButton(
                            icon: Icons.dashboard_rounded,
                            text: 'Dashboard',
                            textStyle: _selectedIndex == 0
                                ? TextStyle(
                                    fontWeight: FontWeight.w600,
                                    foreground: Paint()
                                      ..shader = linearGradient,
                                  )
                                : null,
                          ),
                          GButton(
                            icon: Icons.add_circle_outline,
                            text: 'Add New',
                            textStyle: _selectedIndex == 1
                                ? TextStyle(
                                    fontWeight: FontWeight.w600,
                                    foreground: Paint()
                                      ..shader = linearGradient,
                                  )
                                : null,
                          ),
                          GButton(
                            icon: Icons.history,
                            text: 'History',
                            textStyle: _selectedIndex == 2
                                ? TextStyle(
                                    fontWeight: FontWeight.w600,
                                    foreground: Paint()
                                      ..shader = linearGradient,
                                  )
                                : null,
                          ),
                        ],
                        selectedIndex: _selectedIndex,
                        onTabChange: (index) {
                          setState(() {
                            _selectedIndex = index;
                          });
                        },
                      );
                    }),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
