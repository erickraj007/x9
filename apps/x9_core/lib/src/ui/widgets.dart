import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../offline_cache.dart';
import 'theme.dart';
import 'dialogs.dart';

final NumberFormat _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
final NumberFormat _inr0 = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// Paise -> "₹1,250.00" (Indian grouping). [compact] drops ".00" for whole rupees.
String money(num? paise, {bool compact = false}) {
  if (paise == null) return '—';
  final r = paise / 100;
  if (compact && paise % 100 == 0) return _inr0.format(r);
  return _inr.format(r);
}

/// "1250.50" or "1,250" typed by a person -> paise. Returns null when not a positive amount.
int? toPaise(String text) {
  final v = double.tryParse(text.replaceAll(',', '').replaceAll('₹', '').trim());
  if (v == null || v <= 0) return null;
  return (v * 100).round();
}

String fmtDate(dynamic iso) {
  if (iso == null) return '—';
  final d = DateTime.tryParse(iso.toString());
  if (d == null) return iso.toString();
  return DateFormat('d MMM yyyy, h:mm a').format(d.toLocal());
}

int asInt(dynamic v) => v is int ? v : v is num ? v.toInt() : int.tryParse('${v ?? 0}') ?? double.tryParse('${v ?? 0}')?.toInt() ?? 0;
double asDouble(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? 0}') ?? 0;

void showError(BuildContext context, Object e) {
  if (e is ApiException) {
    if (e.code == 'CANCELLED') return; // the person pressed Cancel on a confirmation pop-up
    final info = classifyError(e);
    if (info != null && context.mounted) {
      showErrorDialog(context, e, info: info); // low balance / user not valid / server down / settlement failed
      return;
    }
  }
  final msg = e is ApiException ? e.display : e.toString();
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      backgroundColor: X9Colors.error,
      content: Row(children: [
        const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: const TextStyle(color: Colors.white))),
      ]),
    ));
}

void showOk(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      backgroundColor: X9Colors.success,
      content: Row(children: [
        const Icon(Icons.check_circle_outline_rounded, color: X9Colors.lightText, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: const TextStyle(color: X9Colors.lightText, fontWeight: FontWeight.w500))),
      ]),
    ));
}

/// Loads [future] and renders loading / error (with retry) / data.
class AsyncView<T> extends StatefulWidget {
  const AsyncView({super.key, required this.load, required this.builder, this.empty});
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;
  final Widget? empty;

  @override
  State<AsyncView<T>> createState() => _AsyncViewState<T>();
}

class _AsyncViewState<T> extends State<AsyncView<T>> {
  late Future<T> _f = widget.load();

  Future<void> _reload() async {
    final f = widget.load();
    setState(() => _f = f);
    await f.then((_) {}, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _f,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) {
          return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
        }
        if (s.hasError) {
          return ErrorRetry(message: s.error is ApiException ? (s.error as ApiException).display : '${s.error}', onRetry: _reload);
        }
        return widget.builder(context, s.data as T, _reload);
      },
    );
  }
}

class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off_rounded, size: 48, color: context.x9.textMuted),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Try again')),
          ]),
        ),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle});
  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Column(children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: context.x9.primarySoft, shape: BoxShape.circle),
            child: Icon(icon, color: X9Colors.primary, size: 34),
          ),
          const SizedBox(height: 14),
          Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle!, style: TextStyle(color: context.x9.textSecondary), textAlign: TextAlign.center),
          ],
        ]),
      );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 12, 10),
        child: Row(children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
          if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
        ]),
      );
}

/// Button that shows a spinner while [onPressed] runs and reports errors.
class BusyButton extends StatefulWidget {
  const BusyButton({super.key, required this.label, required this.onPressed, this.icon, this.outlined = false});
  final String label;
  final Future<void> Function() onPressed;
  final IconData? icon;
  final bool outlined;

  @override
  State<BusyButton> createState() => _BusyButtonState();
}

class _BusyButtonState extends State<BusyButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onPressed();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = _busy
        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
        : Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
            if (widget.icon != null) ...[Icon(widget.icon, size: 20), const SizedBox(width: 8)],
            Text(widget.label),
          ]);
    return widget.outlined
        ? OutlinedButton(onPressed: _busy ? null : _run, child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)) : child)
        : FilledButton(onPressed: _busy ? null : _run, child: child);
  }
}

/// Rounded status chip coloured by meaning. Always shows an icon and the status text.
class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final String? status;

  @override
  Widget build(BuildContext context) {
    final p = context.x9;
    final s = (status ?? '—').toUpperCase();
    Color c = p.textSecondary;
    IconData icon = Icons.info_outline_rounded;
    if (['SUCCESS', 'PAID', 'ACTIVE', 'COMPLETED', 'VERIFIED', 'REDEEMED'].contains(s)) {
      c = X9Colors.success;
      icon = Icons.check_circle_rounded;
    }
    if (['PENDING', 'REQUESTED', 'PROCESSING', 'ISSUED', 'CREATED', 'INITIATED', 'PLACED', 'PREPARING', 'DISPATCHED'].contains(s)) {
      c = X9Colors.warning;
      icon = Icons.schedule_rounded;
    }
    if (['FAILED', 'REJECTED', 'BLOCKED', 'EXPIRED', 'CANCELLED', 'REVERSED'].contains(s)) {
      c = X9Colors.error;
      icon = Icons.cancel_rounded;
    }
    final fg = c == p.textSecondary ? c : p.statusText(c);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: c),
        const SizedBox(width: 4),
        Text(s.replaceAll('_', ' '), style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
      ]),
    );
  }
}

/// Network image with a soft placeholder (logos, banners).
class NetImage extends StatelessWidget {
  const NetImage(this.url, {super.key, this.fit = BoxFit.cover, this.placeholder});
  final String? url;
  final BoxFit fit;
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) {
    final ph = placeholder ?? Container(color: context.x9.primarySoft, child: const Icon(Icons.storefront_rounded, color: X9Colors.primary));
    if (url == null || url!.isEmpty) return ph;
    if (OfflineCache.instance.enabled) return _SavedImage(url: url!, fit: fit, placeholder: ph); // v6.17: pictures work offline
    return Image.network(url!, fit: fit, errorBuilder: (_, __, ___) => ph, loadingBuilder: (c, child, p) => p == null ? child : ph);
  }
}

/// v6.17: picture kept on the phone so it still shows without internet.
class _SavedImage extends StatefulWidget {
  const _SavedImage({required this.url, required this.fit, required this.placeholder});
  final String url;
  final BoxFit fit;
  final Widget placeholder;

  @override
  State<_SavedImage> createState() => _SavedImageState();
}

class _SavedImageState extends State<_SavedImage> {
  late Future<Uint8List?> _bytes = OfflineCache.instance.image(widget.url);

  @override
  void didUpdateWidget(covariant _SavedImage old) {
    super.didUpdateWidget(old);
    if (OfflineCache.imageKey(old.url) != OfflineCache.imageKey(widget.url)) _bytes = OfflineCache.instance.image(widget.url);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
        future: _bytes,
        builder: (_, s) => s.data == null
            ? widget.placeholder
            : Image.memory(s.data!, fit: widget.fit, gaplessPlayback: true, errorBuilder: (_, __, ___) => widget.placeholder),
      );
}

/// Letter avatar used when a merchant has no logo. Red gradient tile with a white letter.
/// Pass [ringColor] (e.g. white) when the avatar sits on a red hero card so it stays visible.
class LetterAvatar extends StatelessWidget {
  const LetterAvatar(this.name, {super.key, this.size = 44, this.url, this.ringColor});
  final String? name;
  final double size;
  final String? url;
  final Color? ringColor;

  @override
  Widget build(BuildContext context) {
    final letter = (name ?? '?').trim().isEmpty ? '?' : name!.trim()[0].toUpperCase();
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(gradient: X9Colors.heroGradient, borderRadius: BorderRadius.circular(size * 0.3)),
      child: Text(letter, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: size * 0.42)),
    );
    final Widget avatar = (url == null || url!.isEmpty)
        ? fallback
        : ClipRRect(
            borderRadius: BorderRadius.circular(size * 0.3),
            child: SizedBox(width: size, height: size, child: NetImage(url, fit: BoxFit.cover, placeholder: fallback)),
          );
    if (ringColor == null) return avatar;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(border: Border.all(color: ringColor!, width: 2), borderRadius: BorderRadius.circular(size * 0.3 + 4)),
      child: avatar,
    );
  }
}

/// White pill for placing a [StatusChip] (or any status / tinted widget) on a red hero card. The
/// child is always drawn with the light palette so its text stays readable in dark mode too.
class HeroPill extends StatelessWidget {
  const HeroPill({super.key, required this.child});
  final Widget child;

  static final ThemeData _light = x9LightTheme();

  @override
  Widget build(BuildContext context) => Theme(
        data: _light,
        child: DecoratedBox(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
          child: child,
        ),
      );
}
