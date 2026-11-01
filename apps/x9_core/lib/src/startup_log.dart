import 'dart:async';

import 'session.dart';

/// Short log of what happened while the app started (init steps that failed or timed out, uncaught errors).
/// Kept in memory and mirrored to the secure store so the NEXT launch (and Server settings > Copy diagnostics)
/// can show what went wrong even when the screen stayed blank. Never throws.
class StartupLog {
  StartupLog._();

  static const _key = 'startup_log';
  static const _maxLines = 80;
  static const _maxChars = 8000;

  static final List<String> _lines = <String>[];
  static String _previous = '';
  static Timer? _flush;

  /// Lines of this run, oldest first.
  static List<String> get lines => List<String>.unmodifiable(_lines);

  /// The log saved by the previous run ('' when none).
  static String get previousRun => _previous;

  /// Adds a line (timestamped) and schedules a save.
  static void add(String message) {
    try {
      final t = DateTime.now().toIso8601String().substring(11, 19);
      _lines.add('$t $message');
      while (_lines.length > _maxLines) {
        _lines.removeAt(0);
      }
      _scheduleSave();
    } catch (_) {}
  }

  /// Adds an error with a short stack excerpt.
  static void error(String where, Object error, [StackTrace? stack]) {
    var text = '$where: $error';
    if (stack != null) {
      final top = stack.toString().split('\n').where((l) => l.trim().isNotEmpty).take(3).join(' | ');
      if (top.isNotEmpty) text = '$text  [$top]';
    }
    if (text.length > 600) text = '${text.substring(0, 600)}...';
    add(text);
  }

  /// Loads the previous run's log from the secure store (with a timeout). Never throws.
  static Future<void> loadPrevious() async {
    try {
      _previous = await SessionStore.instance.read(_key).timeout(const Duration(seconds: 3)) ?? '';
    } catch (_) {
      _previous = '';
    }
  }

  /// Everything, for the diagnostics text.
  static String dump() {
    final b = StringBuffer();
    if (_lines.isEmpty) {
      b.writeln('(no startup problems recorded in this run)');
    } else {
      _lines.forEach(b.writeln);
    }
    if (_previous.trim().isNotEmpty) {
      b.writeln('--- previous run ---');
      b.writeln(_previous.trim());
    }
    return b.toString().trimRight();
  }

  static void _scheduleSave() {
    _flush?.cancel();
    _flush = Timer(const Duration(milliseconds: 400), () async {
      try {
        var text = _lines.join('\n');
        if (text.length > _maxChars) text = text.substring(text.length - _maxChars);
        await SessionStore.instance.write(_key, text).timeout(const Duration(seconds: 3));
      } catch (_) {}
    });
  }
}
