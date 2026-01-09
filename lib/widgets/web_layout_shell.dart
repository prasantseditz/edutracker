import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../screens/dashboard_screen.dart';
import '../screens/add_new_screen.dart';
import '../screens/history_screen.dart';
import '../widgets/confirmation_dialog.dart';

class WebLayoutShell extends StatefulWidget {
  const WebLayoutShell({super.key});

  @override
  State<WebLayoutShell> createState() => _WebLayoutShellState();
}

class _WebLayoutShellState extends State<WebLayoutShell> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const DashboardScreen(),
    const AddNewScreen(),
    const HistoryScreen(),
  ];

  Future<void> _handlePop(bool didPop) async {
    if (didPop) return;

    if (_selectedIndex != 0) {
      setState(() {
        _selectedIndex = 0;
      });
      return;
    }

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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Gradient shader for active text
    final Shader linearGradient = const LinearGradient(
      colors: [Colors.purpleAccent, Colors.blueAccent],
    ).createShader(const Rect.fromLTWH(0.0, 0.0, 200.0, 70.0));

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) => _handlePop(didPop),
      child: Scaffold(
        body: Row(
          children: [
            // Side Navigation
            Container(
              width: 250,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(4, 0),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const SizedBox(height: 32),
                  // App Logo/Title Area
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.asset(
                            'assets/New logo Edutracker.jpg',
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'EduTrack',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            foreground: Paint()..shader = linearGradient,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 48),

                  // Navigation Items
                  _SidebarItem(
                    icon: Icons.dashboard_rounded,
                    label: 'Dashboard',
                    isSelected: _selectedIndex == 0,
                    onTap: () => setState(() => _selectedIndex = 0),
                    gradient: linearGradient,
                    isDark: isDark,
                  ),
                  _SidebarItem(
                    icon: Icons.add_circle_outline,
                    label: 'Add New',
                    isSelected: _selectedIndex == 1,
                    onTap: () => setState(() => _selectedIndex = 1),
                    gradient: linearGradient,
                    isDark: isDark,
                  ),
                  _SidebarItem(
                    icon: Icons.history,
                    label: 'History',
                    isSelected: _selectedIndex == 2,
                    onTap: () => setState(() => _selectedIndex = 2),
                    gradient: linearGradient,
                    isDark: isDark,
                  ),
                ],
              ),
            ),

            // Main Content Area
            Expanded(
              child: IndexedStack(
                index: _selectedIndex,
                children: _screens,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final Shader gradient;
  final bool isDark;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.gradient,
    required this.isDark,
  });

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    // final colorScheme = Theme.of(context).colorScheme; // Removed unused variable

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? (widget.isDark
                    ? Colors.deepPurple.withValues(alpha: 0.2)
                    : Colors.deepPurpleAccent.withValues(alpha: 0.1))
                : (_isHovered
                    ? (widget.isDark ? Colors.grey[800] : Colors.grey[100])
                    : Colors.transparent),
            borderRadius: BorderRadius.circular(12),
            border: widget.isSelected
                ? Border.all(
                    color: Colors.blueAccent.withValues(alpha: 0.5), width: 1)
                : Border.all(color: Colors.transparent),
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                color: widget.isSelected
                    ? Colors.blueAccent
                    : (widget.isDark ? Colors.grey[400] : Colors.grey[600]),
                size: 24,
              ),
              const SizedBox(width: 16),
              Text(
                widget.label,
                style: widget.isSelected
                    ? TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        foreground: Paint()..shader = widget.gradient,
                      )
                    : TextStyle(
                        fontSize: 16,
                        color:
                            widget.isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
