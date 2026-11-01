import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bootstrap.dart';
import 'server_settings_screen.dart';

/// A visible error screen that never depends on the app theme, a Scaffold, a MediaQuery or any asset, so it
/// can be shown even when the rest of the UI failed to build. Plain colours only.
///
/// Used by [runX9App] as the replacement for a widget that threw while building (instead of the blank / grey
/// box release builds show), and by the apps' root gate when starting up failed.
/// Technical details (exception text, server address) are hidden in every normal build. A developer can show them
/// with `--dart-define=X9_SHOW_TECH=true` on a private test build only.
const bool kShowTechnicalDetails = bool.fromEnvironment('X9_SHOW_TECH', defaultValue: false);

class X9ErrorPanel extends StatelessWidget {
  const X9ErrorPanel({
    super.key,
    this.title = 'Something went wrong',
    required this.message,
    this.detail,
    this.onRetry,
    this.showServerSettings = true,
    this.extraActions = const <Widget>[],
    this.forceFull = false,
  });

  final String title;
  final String message;

  /// Technical text (exception, status) shown small under the message and copied by "Copy details".
  final String? detail;

  /// Retry button; null hides it. [X9Bootstrap.restart] is a good default for build errors.
  final VoidCallback? onRetry;
  final bool showServerSettings;

  /// More buttons below (for example "Sign out").
  final List<Widget> extraActions;

  /// Always draw the full panel, never the compact variant.
  final bool forceFull;

  static const Color _bg = Color(0xFFFFFFFF);
  static const Color _text = Color(0xFF121212);
  static const Color _muted = Color(0xFF5F5F66);
  static const Color _red = Color(0xFFE61C24);
  static const Color _soft = Color(0xFFF2F2F4);

  /// Builder for `ErrorWidget.builder`.
  static Widget fromFlutterError(FlutterErrorDetails d) {
    var text = 'Unknown error';
    try {
      text = d.exceptionAsString();
      if (text.length > 400) text = '${text.substring(0, 400)}...';
    } catch (_) {}
    return X9ErrorPanel(
      title: 'This screen could not be shown',
      message: 'Something went wrong while drawing this screen. Please try again.',
      detail: text,
      onRetry: X9Bootstrap.restart,
    );
  }

  /// A small text-button style that needs no Material ancestor.
  static Widget plainButton(String label, VoidCallback onTap, {bool filled = false}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44, minWidth: 120),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? _red : _bg,
          border: Border.all(color: filled ? _red : const Color(0xFFBDBDC4)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(color: filled ? _bg : _text, fontSize: 15, fontWeight: FontWeight.w600, decoration: TextDecoration.none),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(builder: (context, c) {
        final big = c.hasBoundedWidth && c.hasBoundedHeight && c.maxWidth >= 260 && c.maxHeight >= 300;
        if (!big && !forceFull) return _compact();
        return _full(context);
      }),
    );
  }

  Widget _compact() => FittedBox(
        fit: BoxFit.scaleDown,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: const Color(0xFFFFEBEC),
          child: const Text(
            'Error',
            style: TextStyle(color: _red, fontSize: 11, fontWeight: FontWeight.w600, decoration: TextDecoration.none),
          ),
        ),
      );

  Widget _full(BuildContext context) {
    final pad = MediaQuery.maybeOf(context)?.padding ?? EdgeInsets.zero;
    final d = kShowTechnicalDetails ? detail : null;
    return DefaultTextStyle(
      style: const TextStyle(color: _text, fontSize: 15, decoration: TextDecoration.none, fontWeight: FontWeight.w400),
      child: Container(
        color: _bg,
        width: double.infinity,
        height: double.infinity,
        padding: EdgeInsets.fromLTRB(24, 24 + pad.top, 24, 24 + pad.bottom),
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Icon(Icons.error_outline_rounded, size: 52, color: _red),
                const SizedBox(height: 14),
                Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: _text, decoration: TextDecoration.none)),
                const SizedBox(height: 10),
                Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, height: 1.4, color: _muted, decoration: TextDecoration.none)),
                if (d != null && d.trim().isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: _soft, borderRadius: BorderRadius.circular(8)),
                    child: Text(d, maxLines: 8, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, height: 1.35, color: _muted, decoration: TextDecoration.none)),
                  ),
                ],
                const SizedBox(height: 22),
                Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 10, children: [
                  if (onRetry != null) plainButton('Retry', onRetry!, filled: true),
                  if (kShowTechnicalDetails && showServerSettings && ServerSettingsAccess.enabled) plainButton('Server settings', () => openServerSettings(context)),
                  if (d != null && d.trim().isNotEmpty)
                    plainButton('Copy details', () {
                      Clipboard.setData(ClipboardData(text: '$title\n$message\n$d'));
                    }),
                  ...extraActions,
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
