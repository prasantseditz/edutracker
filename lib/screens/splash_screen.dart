import 'package:flutter/material.dart';
import 'package:animated_splash_screen/animated_splash_screen.dart';
import 'package:page_transition/page_transition.dart';
import '../widgets/bottom_nav_shell.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedSplashScreen(
      splash: _LogoAnimation(),
      backgroundColor: Colors.white,
      splashIconSize: 200,
      duration: 3000, // ২.৫ সেকেন্ড
      nextScreen: const BottomNavShell(), // Main app screen
      splashTransition: SplashTransition.fadeTransition,
      pageTransitionType: PageTransitionType.fade,
    );
  }
}

class _LogoAnimation extends StatefulWidget {
  const _LogoAnimation();

  @override
  State<_LogoAnimation> createState() => _LogoAnimationState();
}

class _LogoAnimationState extends State<_LogoAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    // Bounce-like water drop effect
    _animation = TweenSequence([
      TweenSequenceItem(
          tween: Tween<double>(begin: 1.0, end: 0.85)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 50),
      TweenSequenceItem(
          tween: Tween<double>(begin: 0.85, end: 1.2)
              .chain(CurveTween(curve: Curves.elasticOut)),
          weight: 50),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _animation,
      child: Image.asset('assets/logo.png'),
    );
  }
}
