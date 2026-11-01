import 'package:flutter/material.dart';
import 'package:x9_core/x9_core.dart';

/// Pulsing grey placeholder while content loads.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.width, this.height = 14, this.radius = 10, this.circle = false});
  final double? width;
  final double height;
  final double radius;
  final bool circle;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.x9;
    final base = p.isDark ? p.card : p.border;
    final hi = p.isDark ? p.border : p.surface;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Color.lerp(base, hi, _c.value),
          shape: widget.circle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: widget.circle ? null : BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// A list of card-shaped skeleton rows.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 6, this.padding = const EdgeInsets.all(16)});
  final int count;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: padding,
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, __) => const SkeletonTile(),
      );
}

class SkeletonTile extends StatelessWidget {
  const SkeletonTile({super.key});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            const Skeleton(width: 48, height: 48, radius: 14),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                Skeleton(width: 160, height: 14),
                SizedBox(height: 8),
                Skeleton(width: 100, height: 11),
              ]),
            ),
            const Skeleton(width: 54, height: 18),
          ]),
        ),
      );
}

/// Red gradient circle icon used in headers and empty sections.
class GradientIcon extends StatelessWidget {
  const GradientIcon(this.icon, {super.key, this.size = 56});
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(gradient: X9Colors.heroGradient, shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: size * 0.5),
      );
}
