import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/edutrack_provider.dart';
import 'app_locking_screen.dart';
import '../app_globals.dart';
import '../widgets/responsive_container.dart';

class SettingsScreen extends StatefulWidget {
  static const routeName = '/settings-screen';
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<EduTrackProvider>(context);
    final theme = Theme.of(context);
    final isOrgMode = provider.appMode == 'org';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: provider.appColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ResponsiveContainer(
        maxWidth: 600,
        child: ListView(
          children: [
            const SizedBox(height: 16),

            // App Mode Section
            _buildSectionHeader('APPLICATION MODE'),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.swap_horizontal_circle,
                        color: Colors.blue),
                    title: const Text('App Context'),
                    subtitle: Text(
                        isOrgMode ? 'Organization / School' : 'Private Tutor'),
                    trailing: Switch(
                      value: isOrgMode,
                      activeThumbColor: Colors.tealAccent,
                      onChanged: (value) async {
                        final newMode = value ? 'org' : 'tutor';
                        final confirmed =
                            await _showModeSwitchDialog(context, newMode);
                        if (confirmed) {
                          await provider.setAppMode(newMode);
                          if (mounted) {
                            // ignore: use_build_context_synchronously
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(
                                      'Switched to ${value ? 'Organization' : 'Tutor'} Mode')),
                            );
                          }
                        }
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Text(
                      'Note: Tutor and Organization modes have separate data storage. Switching will hide data from the other mode.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Security Section
            _buildSectionHeader('SECURITY'),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: ListTile(
                leading: const Icon(Icons.lock, color: Colors.orange),
                title: const Text('App Locking (PIN)'),
                subtitle: const Text('Configure app lock and PIN'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  try {
                    final nav = rootNavigatorKey.currentState;
                    if (nav != null) {
                      nav.pushNamed(AppLockingScreen.routeName);
                    }
                  } catch (e) {
                    Navigator.of(context, rootNavigator: true)
                        .pushNamed(AppLockingScreen.routeName);
                  }
                },
              ),
            ),

            const SizedBox(height: 16),

            // About Section
            _buildSectionHeader('ABOUT'),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: const Column(
                children: [
                  ListTile(
                    leading: Icon(Icons.info, color: Colors.grey),
                    title: Text('Version'),
                    trailing:
                        Text('1.2.0', style: TextStyle(color: Colors.grey)),
                  ),
                ],
              ),
            ),
          ],
        ), // ListView
      ), // ResponsiveContainer
    ); // Scaffold
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Future<bool> _showModeSwitchDialog(
      BuildContext context, String newMode) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Switch Mode?'),
            content: Text(
                'Are you sure you want to switch to ${newMode == 'org' ? 'Organization' : 'Private Tutor'} mode?\n\nEach mode uses its own separate database.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Switch'),
              ),
            ],
          ),
        ) ??
        false;
  }
}
