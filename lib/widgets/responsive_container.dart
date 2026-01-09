import 'package:flutter/material.dart';

class ResponsiveContainer extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final bool addCardEffect;
  final EdgeInsets? padding;

  const ResponsiveContainer({
    super.key,
    required this.child,
    this.maxWidth = 800,
    this.addCardEffect = true,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // If on mobile (small screen), just return the child directly
        // consistent with mobile app behavior.
        if (constraints.maxWidth < 800) {
          return child;
        }

        // On Web/Desktop: Center and constrain content
        return Center(
          child: Container(
            constraints: BoxConstraints(maxWidth: maxWidth),
            margin: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            padding: padding ??
                (addCardEffect ? const EdgeInsets.all(32) : EdgeInsets.zero),
            decoration: addCardEffect
                ? BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  )
                : null,
            child: child,
          ),
        );
      },
    );
  }
}
