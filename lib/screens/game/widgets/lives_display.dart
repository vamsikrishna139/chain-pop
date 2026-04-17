import 'package:flutter/material.dart';

class LivesDisplay extends StatelessWidget {
  final int livesRemaining;
  final int maxLives;

  const LivesDisplay({
    super.key,
    required this.livesRemaining,
    this.maxLives = 3,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(maxLives, (i) {
        final alive = i < livesRemaining;
        return Padding(
          padding: EdgeInsets.only(left: i > 0 ? 4.0 : 0),
          child: AnimatedScale(
            scale: alive ? 1.0 : 0.7,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutBack,
            child: AnimatedOpacity(
              opacity: alive ? 1.0 : 0.3,
              duration: const Duration(milliseconds: 400),
              child: Icon(
                alive ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: alive ? Colors.redAccent : Colors.white38,
                size: 20,
                shadows: alive
                    ? [
                        Shadow(
                          color: Colors.redAccent.withOpacity(0.5),
                          blurRadius: 8,
                        )
                      ]
                    : [],
              ),
            ),
          ),
        );
      }),
    );
  }
}
