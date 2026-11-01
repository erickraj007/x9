import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../util/data_uri.dart';

/// The server's dynamic UPI QR (`qr` data-URI image). Falls back to drawing the `upi://` intent as a QR
/// when the image is missing or cannot be decoded.
class UpiQrImage extends StatelessWidget {
  const UpiQrImage({super.key, this.qr, this.intent, this.size = 220});
  final String? qr;
  final String? intent;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = (intent ?? '').isEmpty
        ? SizedBox(width: size, height: size, child: const Center(child: Text('UPI request unavailable')))
        : QrImageView(data: intent!, size: size, backgroundColor: Colors.white);
    final bytes = decodeImageDataUri(qr);
    if (bytes == null) return fallback;
    return Image.memory(
      bytes,
      width: size,
      height: size,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}
