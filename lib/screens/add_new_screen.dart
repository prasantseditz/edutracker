import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/edutrack_provider.dart';
import '../services/ad_manager.dart';

class AddNewScreen extends StatefulWidget {
  const AddNewScreen({super.key});

  @override
  State<AddNewScreen> createState() => _AddNewScreenState();
}

class _AddNewScreenState extends State<AddNewScreen> {
  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<EduTrackProvider>(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Add New')),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(children: [
                _ActionCard(
                  icon: Icons.person_add_alt,
                  title: 'Add a Single Student',
                  subtitle: 'Create a new profile for one student.',
                  onTap: () => Navigator.pushNamed(context, '/add-student'),
                  iconColor: Colors.green.shade700,
                  titleColor: Colors.green.shade900,
                  subtitleColor: Colors.green.shade700,
                  gradientColors: [
                    Colors.purple.shade100,
                    Colors.deepPurple.shade100
                  ],
                ),
                const SizedBox(height: 12),
                _ActionCard(
                  icon: Icons.group_add,
                  title: 'Create a New ${provider.batchLabel}',
                  subtitle:
                      'Add a ${provider.batchLabel.toLowerCase()} with multiple students at once.',
                  onTap: () => Navigator.pushNamed(context, '/create-batch'),
                  iconColor: Colors.blue.shade700,
                  titleColor: Colors.blue.shade900,
                  subtitleColor: Colors.blue.shade700,
                  gradientColors: [
                    Colors.indigo.shade100,
                    Colors.blue.shade100
                  ],
                ),
              ]),
            ),
          ),

          // 🟩 নিচে ব্যানার বিজ্ঞাপন
          // 🟩 নিচে ব্যানার বিজ্ঞাপন
          const SafeArea(
            child: BannerAdWidget(),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color iconColor;
  final Color titleColor;
  final Color subtitleColor;
  final List<Color> gradientColors;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.iconColor,
    required this.titleColor,
    required this.subtitleColor,
    required this.gradientColors,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 64, color: iconColor),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: titleColor,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: subtitleColor,
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
