// lib/widgets/stylish_search_bar.dart
import 'package:flutter/material.dart';

class StylishSearchBar extends StatefulWidget {
  final String hintText;
  final ValueChanged<String> onChanged;

  const StylishSearchBar({
    super.key,
    required this.hintText,
    required this.onChanged,
  });

  @override
  State<StylishSearchBar> createState() => _StylishSearchBarState();
}

class _StylishSearchBarState extends State<StylishSearchBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  final TextEditingController _controllerText = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _animation = Tween<double>(begin: 1.0, end: 1.02).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _controllerText.dispose();
    super.dispose();
  }

  void _onTap() {
    _controller.forward().then((_) => _controller.reverse());
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _animation,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12.0),
          boxShadow: [
            BoxShadow(
              color: const Color.fromARGB(255, 0, 97, 207)
                  .withAlpha((255 * 0.04).round()),
              spreadRadius: 1,
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: TextField(
          controller: _controllerText,
          onChanged: widget.onChanged,
          onTap: _onTap,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search, color: Colors.deepPurple),
            hintText: widget.hintText,
            hintStyle: TextStyle(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white60
                  : Colors.black54,
            ),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.0),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.0),
              borderSide:
                  const BorderSide(color: Colors.deepPurple, width: 2.0),
            ),
            contentPadding:
                const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
          ),
        ),
      ),
    );
  }
}
