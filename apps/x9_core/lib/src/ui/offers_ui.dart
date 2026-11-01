import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'theme.dart';
import 'widgets.dart';

/// URLs from an image list that holds plain strings or `{id, url, sort_order}` objects (sorted by sort_order).
List<String> imageUrlsOf(dynamic images) {
  if (images is! List) return const [];
  final rows = <MapEntry<int, String>>[];
  var i = 0;
  for (final raw in images) {
    String? url;
    var order = i;
    if (raw is String) {
      url = raw;
    } else if (raw is Map) {
      final u = raw['url'];
      if (u != null) url = u.toString();
      final o = raw['sort_order'];
      if (o is num) order = o.toInt();
    }
    if (url != null && url.isNotEmpty) rows.add(MapEntry(order * 1000 + i, url));
    i++;
  }
  rows.sort((a, b) => a.key.compareTo(b.key));
  return [for (final r in rows) r.value];
}

/// "10 Oct, 10:00 AM" in Indian Standard Time (UTC+5:30), whatever the phone's own zone is.
String fmtIst(dynamic iso) {
  if (iso == null) return '—';
  final d = DateTime.tryParse(iso.toString());
  if (d == null) return iso.toString();
  final ist = d.toUtc().add(const Duration(hours: 5, minutes: 30));
  return DateFormat('d MMM, h:mm a').format(ist);
}

/// "2d 4h" / "3h 12m" / "12m 05s" / "45s". Empty when [d] is zero or negative.
String fmtDuration(Duration d) {
  if (d.inSeconds <= 0) return '';
  if (d.inDays >= 1) return '${d.inDays}d ${d.inHours % 24}h';
  if (d.inHours >= 1) return '${d.inHours}h ${(d.inMinutes % 60).toString().padLeft(2, '0')}m';
  if (d.inMinutes >= 1) return '${d.inMinutes}m ${(d.inSeconds % 60).toString().padLeft(2, '0')}s';
  return '${d.inSeconds}s';
}

/// Live countdown text: "Ends in 2d 4h" until [target], then [doneText]. Ticks every second in the last hour and
/// every 30 s before that. Disposes its timer.
class Countdown extends StatefulWidget {
  const Countdown({super.key, required this.target, this.prefix = 'Ends in ', this.doneText = 'Ended', this.style, this.icon = true, this.color});

  final DateTime? target;
  final String prefix;
  final String doneText;
  final TextStyle? style;
  final bool icon;
  final Color? color;

  @override
  State<Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<Countdown> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(covariant Countdown old) {
    super.didUpdateWidget(old);
    if (old.target != widget.target) _arm();
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Duration? get _left => widget.target?.difference(DateTime.now());

  void _arm() {
    _t?.cancel();
    final left = _left;
    if (left == null || left.inSeconds <= 0) return;
    _t = Timer(left.inHours >= 1 ? const Duration(seconds: 30) : const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() {});
      _arm();
    });
  }

  @override
  Widget build(BuildContext context) {
    final left = _left;
    if (left == null) return const SizedBox.shrink();
    final done = left.inSeconds <= 0;
    final urgent = !done && left.inHours < 6;
    final p = context.x9;
    final c = widget.color ?? (done ? p.textSecondary : (urgent ? p.statusText(X9Colors.warning) : p.onPrimarySoft));
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (widget.icon) ...[Icon(done ? Icons.timer_off_rounded : Icons.timer_rounded, size: 14, color: c), const SizedBox(width: 4)],
      Flexible(
        child: Text(
          done ? widget.doneText : '${widget.prefix}${fmtDuration(left)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: (widget.style ?? const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)).copyWith(color: c),
        ),
      ),
    ]);
  }
}

/// Swipeable image gallery (PageView) with dots. Shows a branded placeholder when [urls] is empty.
class ImageCarousel extends StatefulWidget {
  const ImageCarousel({super.key, required this.urls, this.aspectRatio = 16 / 10, this.radius = 0, this.onTap, this.placeholderIcon = Icons.local_offer_rounded, this.fit = BoxFit.cover});

  final List<String> urls;
  final double aspectRatio;
  final double radius;
  final void Function(int index)? onTap;
  final IconData placeholderIcon;
  final BoxFit fit;

  @override
  State<ImageCarousel> createState() => _ImageCarouselState();
}

class _ImageCarouselState extends State<ImageCarousel> {
  final PageController _c = PageController();
  int _i = 0;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.x9;
    final urls = widget.urls;
    final Widget body;
    if (urls.isEmpty) {
      body = Container(
        decoration: const BoxDecoration(gradient: X9Colors.heroGradient),
        alignment: Alignment.center,
        child: Icon(widget.placeholderIcon, color: Colors.white.withValues(alpha: 0.85), size: 48),
      );
    } else {
      body = Stack(fit: StackFit.expand, children: [
        PageView.builder(
          controller: _c,
          itemCount: urls.length,
          onPageChanged: (v) => setState(() => _i = v),
          itemBuilder: (_, i) => GestureDetector(
            onTap: widget.onTap == null ? null : () => widget.onTap!(i),
            child: NetImage(urls[i], fit: widget.fit, placeholder: Container(color: p.primarySoft, child: const Icon(Icons.image_rounded, color: X9Colors.primary))),
          ),
        ),
        if (urls.length > 1)
          Positioned(
            left: 0,
            right: 0,
            bottom: 8,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < urls.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _i ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(color: i == _i ? Colors.white : Colors.white.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(3)),
                ),
            ]),
          ),
      ]);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: AspectRatio(aspectRatio: widget.aspectRatio, child: body),
    );
  }
}

/// Full-screen, pinch-to-zoom viewer for [urls], opened at [initial].
Future<void> showImageViewer(BuildContext context, List<String> urls, {int initial = 0}) {
  if (urls.isEmpty) return Future<void>.value();
  return Navigator.of(context).push<void>(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => _ImageViewer(urls: urls, initial: initial < 0 || initial >= urls.length ? 0 : initial),
  ));
}

class _ImageViewer extends StatefulWidget {
  const _ImageViewer({required this.urls, required this.initial});
  final List<String> urls;
  final int initial;

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  late final PageController _c = PageController(initialPage: widget.initial);
  late int _i = widget.initial;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_i + 1} / ${widget.urls.length}', style: const TextStyle(fontSize: 15)),
      ),
      body: PageView.builder(
        controller: _c,
        itemCount: widget.urls.length,
        onPageChanged: (v) => setState(() => _i = v),
        itemBuilder: (_, i) => InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(child: Image.network(widget.urls[i], fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_rounded, color: Colors.white54, size: 56))),
        ),
      ),
    );
  }
}

/// Merchant-facing sentence for the `cashback_skipped` reason of a bill. Empty when nothing should be shown.
String cashbackSkippedText(String? reason) {
  switch ((reason ?? '').toUpperCase()) {
    case 'INSUFFICIENT_MERCHANT_BALANCE':
      return 'Cashback not given: your main wallet balance is too low. Add money to your wallet to give cashback.';
    case 'MIN_BILL_NOT_MET':
      return 'Cashback not given: this bill is below the offer\'s minimum bill amount.';
    case 'BUDGET_USED':
      return 'Cashback not given: the cashback budget of this offer is used up.';
    case 'USER_LIMIT':
      return 'Cashback not given: this customer has reached the per-customer limit.';
    default:
      return '';
  }
}
