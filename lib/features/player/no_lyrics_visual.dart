import 'dart:math' as math;

import 'package:flutter/material.dart';

class NoLyricsVisual extends StatefulWidget {
  const NoLyricsVisual({super.key, this.artwork});

  final ImageProvider<Object>? artwork;

  @override
  State<NoLyricsVisual> createState() => _NoLyricsVisualState();
}

class _NoLyricsVisualState extends State<NoLyricsVisual>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Transform.rotate(
        angle: _controller.value * math.pi * 2,
        child: child,
      ),
      child: Container(
        width: 260,
        height: 260,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF121212),
          border: Border.all(color: Colors.white12, width: 18),
          boxShadow: const [
            BoxShadow(
              color: Color(0x55E5484D),
              blurRadius: 48,
              spreadRadius: 8,
            ),
          ],
          image: widget.artwork == null
              ? null
              : DecorationImage(image: widget.artwork!, fit: BoxFit.cover),
        ),
        child: Center(
          child: Container(
            width: 58,
            height: 58,
            decoration: const BoxDecoration(
              color: Color(0xFFE5484D),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.graphic_eq_rounded, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
