import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Small "AD" tag on a toolbar button whose next tap plays a rewarded video,
/// so the player knows before tapping (rewarded ads must be opt-in).
class AdBadge extends StatelessWidget {
  const AdBadge({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'plays a short ad',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(
          'AD',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 8,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ),
    );
  }
}
