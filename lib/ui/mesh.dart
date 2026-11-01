import 'package:flutter/material.dart';

import 'theme.dart';

/// A softly tinted tile for cards and thumbnails. The same [seed] always
/// gives the same tone, and the tint works on both light and dark themes.
class MeshArt extends StatelessWidget {
  const MeshArt({super.key, required this.seed, this.radius = Radii.md, this.child});
  final String seed;
  final double radius;
  final Widget? child;

  static const _tones = <Color>[
    Color(0xFFF97316), // orange
    Color(0xFFEC4899), // pink
    Color(0xFF8B5CF6), // violet
    Color(0xFF14B8A6), // teal
    Color(0xFF84CC16), // lime
    Color(0xFFEAB308), // amber
    Color(0xFF3B82F6), // blue
    Color(0xFFD946EF), // fuchsia
  ];

  /// The strong colour for [seed]; use it for the glyph on the tile.
  static Color tone(String seed) => _tones[_hash(seed) % _tones.length];

  static List<Color> colorsFor(String seed) => [tone(seed)];

  static int _hash(String s) {
    var h = 0;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h;
  }

  @override
  Widget build(BuildContext context) {
    final c = tone(seed);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [c.withValues(alpha: 0.22), c.withValues(alpha: 0.08)],
          ),
        ),
        child: child == null ? const SizedBox.expand() : Stack(fit: StackFit.passthrough, children: [child!]),
      ),
    );
  }
}

/// Coloured icon badge with a ring in the surface colour, meant to overlap
/// the edge of a [MeshArt] image.
class RingBadge extends StatelessWidget {
  const RingBadge({super.key, required this.icon, required this.color, this.size = 40});
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(color: p.surface, width: 3),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.45, color: Colors.white),
    );
  }
}

/// A round avatar: a photo when available, else initials on a tinted tile.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.url, this.size = 40});
  final String name;
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().split(RegExp(r'\s+')).take(2).map((w) => w[0].toUpperCase()).join();
    return SizedBox.square(
      dimension: size,
      child: ClipOval(
        child: url != null
            ? Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, _, _) => _initials(initials))
            : _initials(initials),
      ),
    );
  }

  Widget _initials(String text) => MeshArt(
    seed: name,
    radius: size,
    child: Center(
      child: Text(
        text,
        style: TextStyle(fontSize: size * 0.38, fontWeight: FontWeight.w700, color: MeshArt.tone(name)),
      ),
    ),
  );
}
