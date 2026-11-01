import 'package:flutter/material.dart';

/// The X9 logo (owner-supplied "X9 Ads & Deals" artwork, bundled in this package under
/// `assets/brand/`). Picks the black version on light themes and the white version on dark themes.
///
/// * [X9Logo] / [X9Logo.full]: full lockup with "Ads & Deals" (sign-in screens, splash).
/// * [X9Logo.mark]: the X9 mark only (app bars, drawer headers, receipts).
///
/// Brand rules: keep clear space around the logo (use [padding]), never recolour or stretch it, and
/// place it on white / neutral surfaces, not on red or photo backgrounds. Give [height] OR [width];
/// the aspect ratio is kept.
class X9Logo extends StatelessWidget {
  /// Full lockup (599 x 495).
  const X9Logo({super.key, this.height, this.width, this.padding = EdgeInsets.zero, this.brightness}) : mark = false;

  /// Full lockup (same as the default constructor).
  const X9Logo.full({super.key, this.height, this.width, this.padding = EdgeInsets.zero, this.brightness}) : mark = false;

  /// X9 mark only (599 x 341).
  const X9Logo.mark({super.key, this.height, this.width, this.padding = EdgeInsets.zero, this.brightness}) : mark = true;

  final bool mark;
  final double? height;
  final double? width;
  final EdgeInsetsGeometry padding;

  /// Force a variant (e.g. the light logo inside a printed receipt that is always white).
  /// Null = follow `Theme.of(context).brightness`.
  final Brightness? brightness;

  static const String _pkg = 'x9_core';

  /// Asset path (inside package x9_core) for the given variant.
  static String assetFor({required bool mark, required bool dark}) =>
      'assets/brand/x9-${mark ? 'mark' : 'display-ads'}-${dark ? 'dark' : 'light'}.png';

  @override
  Widget build(BuildContext context) {
    final dark = (brightness ?? Theme.of(context).brightness) == Brightness.dark;
    final img = Image.asset(
      assetFor(mark: mark, dark: dark),
      package: _pkg,
      height: height,
      width: width,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      semanticLabel: mark ? 'X9' : 'X9 Ads & Deals',
    );
    return padding == EdgeInsets.zero ? img : Padding(padding: padding, child: img);
  }
}
