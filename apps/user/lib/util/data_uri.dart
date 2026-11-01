import 'dart:convert';
import 'dart:typed_data';

/// Bytes of a `data:image/png;base64,....` URI, or null when it is not a raster image data URI
/// (SVG data cannot be drawn by Image.memory, so it also returns null).
Uint8List? decodeImageDataUri(String? uri) {
  if (uri == null) return null;
  final s = uri.trim();
  if (!s.toLowerCase().startsWith('data:image/')) return null;
  final comma = s.indexOf(',');
  if (comma < 0) return null;
  final header = s.substring(5, comma).toLowerCase(); // e.g. image/png;base64
  if (header.contains('svg') || !header.contains('base64')) return null;
  try {
    final bytes = base64Decode(s.substring(comma + 1).replaceAll(RegExp(r'\s'), ''));
    return bytes.isEmpty ? null : bytes;
  } catch (_) {
    return null;
  }
}
