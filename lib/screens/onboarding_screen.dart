import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/edutrack_provider.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  OnboardingScreenState createState() => OnboardingScreenState();
}

class OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _nameController = TextEditingController();
  String _selectedMode = ''; // 'tutor' or 'org'
  bool _saving = false;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
    _animController.forward();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _finishOnboarding() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showError('Please enter your name.');
      return;
    }
    if (_selectedMode.isEmpty) {
      _showError('Please select a mode to continue.');
      return;
    }

    setState(() => _saving = true);

    try {
      final provider = context.read<EduTrackProvider>();
      await provider.completeOnboarding(name, _selectedMode);

      // Save to SharedPreferences for fallback consistency
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarding_complete', true);

      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/batches');
    } catch (e) {
      _showError('Failed to save settings: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF04123A), Color(0xFF0F2050)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24.0, vertical: 30),
              child: Column(
                children: [
                  // Header Section
                  const SizedBox(height: 20),
                  Hero(
                    tag: 'app_logo',
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(77),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/New logo Edutracker.jpg',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Welcome to EduTrack',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Smart education management starting with you.',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 40),

                  // Mode Selection Section
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Choose your purpose:',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _ModeCard(
                          title: 'Private Tutor',
                          subtitle: 'Individual batches',
                          icon: Icons.person_search_rounded,
                          isSelected: _selectedMode == 'tutor',
                          onTap: () => setState(() => _selectedMode = 'tutor'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _ModeCard(
                          title: 'Organization',
                          subtitle: 'Schools & centers',
                          icon: Icons.account_balance_rounded,
                          isSelected: _selectedMode == 'org',
                          onTap: () => setState(() => _selectedMode = 'org'),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 40),

                  // Name Input Section
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Your Name:',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white.withAlpha(20),
                      hintText: 'Enter your full name',
                      hintStyle: const TextStyle(color: Colors.white38),
                      prefixIcon:
                          const Icon(Icons.badge, color: Colors.white70),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                            color: Colors.tealAccent, width: 1.5),
                      ),
                    ),
                  ),

                  const SizedBox(height: 50),

                  // Action Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00B4DB), Color(0xFF0083B0)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0083B0).withAlpha(102),
                            blurRadius: 15,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: _saving ? null : _finishOnboarding,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'GET STARTED',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ModeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: 160,
      decoration: BoxDecoration(
        color: isSelected
            ? Colors.tealAccent.withAlpha(38)
            : Colors.white.withAlpha(13),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isSelected ? Colors.tealAccent : Colors.white12,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 48,
                color: isSelected ? Colors.tealAccent : Colors.white60,
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: isSelected ? Colors.white70 : Colors.white38,
                  fontSize: 11,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
