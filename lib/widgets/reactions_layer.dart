import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Emoji that float up over the video and fade out.
class ReactionsLayer extends StatefulWidget {
  const ReactionsLayer({super.key});

  @override
  State<ReactionsLayer> createState() => ReactionsLayerState();
}

class ReactionsLayerState extends State<ReactionsLayer> {
  final _items = <_Floating>[];
  final _rng = Random();
  int _next = 0;

  void spawn(String emoji) {
    if (!mounted || emoji.isEmpty) return;
    setState(() {
      _items.add(
        _Floating(
          id: _next++,
          emoji: emoji,
          // Start somewhere in the right third, drift a little sideways.
          x: 0.62 + _rng.nextDouble() * 0.3,
          drift: (_rng.nextDouble() - 0.5) * 0.12,
        ),
      );
      if (_items.length > 24) _items.removeAt(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, box) => Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // On the web the emoji font loads on first use; laying the
            // reactions out invisibly gets it ready before one arrives.
            if (kIsWeb)
              const Opacity(
                opacity: 0,
                child: Text('❤️😂😮😢👍🔥', style: TextStyle(fontSize: 8)),
              ),
            for (final item in _items)
              TweenAnimationBuilder<double>(
                key: ValueKey(item.id),
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 2400),
                curve: Curves.easeOut,
                onEnd: () {
                  if (mounted) setState(() => _items.remove(item));
                },
                builder: (context, t, child) => Positioned(
                  left: box.maxWidth * (item.x + item.drift * t) - 18,
                  bottom: 24 + (box.maxHeight * 0.6) * t,
                  child: Opacity(
                    opacity: t < 0.7 ? 1 : (1 - (t - 0.7) / 0.3).clamp(0, 1),
                    child: Transform.scale(scale: 0.8 + 0.5 * t, child: child),
                  ),
                ),
                child: Text(item.emoji, style: const TextStyle(fontSize: 34)),
              ),
          ],
        ),
      ),
    );
  }
}

class _Floating {
  _Floating({
    required this.id,
    required this.emoji,
    required this.x,
    required this.drift,
  });

  final int id;
  final String emoji;
  final double x;
  final double drift;
}
