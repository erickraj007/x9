import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'theme.dart';

/// Full-screen QR scanner. Pops with the scanned text, or null when closed.
/// [accept] can reject codes that are not for this screen (keeps scanning).
class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key, this.title = 'Scan QR code', this.hint = 'Point the camera at the QR code', this.accept});
  final String title;
  final String hint;
  final bool Function(String value)? accept;

  static Future<String?> open(BuildContext context, {String title = 'Scan QR code', String hint = 'Point the camera at the QR code', bool Function(String)? accept}) =>
      Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => QrScanPage(title: title, hint: hint, accept: accept)));

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> with WidgetsBindingObserver {
  // autoStart is off: we start the camera ourselves, retry when the phone is slow to release it, and restart on resume.
  final MobileScannerController _c = MobileScannerController(autoStart: false, detectionSpeed: DetectionSpeed.noDuplicates, formats: const [BarcodeFormat.qrCode]);
  bool _done = false;
  bool _starting = false;
  String? _msg;
  MobileScannerException? _err;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startCamera());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _c.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the phone's Settings (camera permission) or another app: try again.
    if (state == AppLifecycleState.resumed && !_done && !_starting && !_c.value.isRunning) _startCamera();
  }

  /// Starts the camera up to 3 times (a permission dialog or another app can still hold the camera for a moment).
  Future<void> _startCamera() async {
    if (_starting || _done || !mounted) return;
    _starting = true;
    setState(() => _err = null);
    MobileScannerException? last;
    for (var i = 0; i < 3 && mounted && !_done; i++) {
      try {
        await _c.start();
        last = _c.value.error;
      } on MobileScannerException catch (e) {
        last = e;
      } catch (_) {
        last = const MobileScannerException(errorCode: MobileScannerErrorCode.genericError);
      }
      if (last == null || last.errorCode == MobileScannerErrorCode.permissionDenied) break;
      await Future<void>.delayed(Duration(milliseconds: 600 * (i + 1)));
    }
    _starting = false;
    if (mounted) setState(() => _err = last);
  }

  /// Opens the phone's own camera app, takes a photo of the QR and reads it. Works when the live preview cannot start.
  Future<void> _takePhoto() async {
    try {
      final f = await ImagePicker().pickImage(source: ImageSource.camera);
      if (f == null) return;
      await _readFile(f.path);
    } catch (_) {
      if (mounted) setState(() => _msg = 'Could not open the camera app. Use Scan from a photo or Enter code manually.');
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      if (_take(b.rawValue)) return;
    }
  }

  bool _take(String? v) {
    if (_done || v == null || v.trim().isEmpty) return false;
    v = v.trim();
    if (widget.accept != null && !widget.accept!(v)) {
      if (mounted) setState(() => _msg = 'This QR code is not an X9 / UPI payment code.');
      return false;
    }
    _done = true;
    Navigator.of(context).pop(v);
    return true;
  }

  /// Fallback when the live camera cannot start: read the QR from a photo / screenshot.
  Future<void> _fromPhoto() async {
    try {
      final f = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (f == null) return;
      await _readFile(f.path);
    } catch (_) {
      if (mounted) setState(() => _msg = 'Could not read that picture. Try another one.');
    }
  }

  Future<void> _readFile(String path) async {
    final cap = await _c.analyzeImage(path);
    var ok = false;
    for (final b in cap?.barcodes ?? const <Barcode>[]) {
      if (_take(b.rawValue)) {
        ok = true;
        break;
      }
    }
    if (!ok && mounted && !_done) setState(() => _msg = 'No payment QR code found in that picture.');
  }

  Future<void> _retry() async {
    try {
      await _c.stop();
    } catch (_) {}
    if (mounted) setState(() => _msg = null);
    await _startCamera();
  }

  /// Fallback: paste the text of the code (x9pay://..., upi://pay?...).
  Future<void> _paste() async {
    final t = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter payment code'),
        content: TextField(controller: t, autofocus: true, minLines: 1, maxLines: 4, decoration: const InputDecoration(hintText: 'Paste the code text or UPI link')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, t.text), child: const Text('Continue')),
        ],
      ),
    );
    t.dispose();
    _take(v);
  }

  Widget _error(BuildContext context, MobileScannerException e) {
    final denied = e.errorCode == MobileScannerErrorCode.permissionDenied;
    final text = denied
        ? 'Camera permission is off. Allow Camera for this app in your phone Settings, then try again.'
        : e.errorCode == MobileScannerErrorCode.unsupported
            ? 'This phone cannot use the camera scanner here.'
            : 'The camera could not start. Close other apps that use the camera, then try again.';
    return Container(
      color: Colors.black,
      width: double.infinity,
      alignment: Alignment.center,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.no_photography_rounded, color: Colors.white, size: 44),
        const SizedBox(height: 14),
        Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4)),
        if ((e.errorDetails?.message ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('(${e.errorDetails!.message})', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 11.5)),
        ],
        if (_msg != null) ...[
          const SizedBox(height: 10),
          Text(_msg!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.amberAccent, fontSize: 13)),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(onPressed: _retry, icon: const Icon(Icons.refresh_rounded), label: const Text('Try again')),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _takePhoto,
          style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
          icon: const Icon(Icons.photo_camera_rounded),
          label: const Text('Take a photo of the QR'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _fromPhoto,
          style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
          icon: const Icon(Icons.photo_library_rounded),
          label: const Text('Scan from a photo'),
        ),
        TextButton(onPressed: _paste, child: const Text('Enter code manually', style: TextStyle(color: Colors.white70))),
      ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(icon: const Icon(Icons.photo_library_rounded), tooltip: 'Scan from a photo', onPressed: _fromPhoto),
          IconButton(icon: const Icon(Icons.flash_on_rounded), onPressed: () => _c.toggleTorch()),
          IconButton(icon: const Icon(Icons.cameraswitch_rounded), onPressed: () => _c.switchCamera()),
        ],
      ),
      body: Stack(children: [
        _err != null
            ? _error(context, _err!)
            : MobileScanner(controller: _c, onDetect: _onDetect, errorBuilder: (context, e, _) => _error(context, e)),
        if (_err == null)
          Center(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(border: Border.all(color: X9Colors.primary, width: 3), borderRadius: BorderRadius.circular(24)),
          ),
        ),
        if (_err == null)
          Positioned(
          left: 24,
          right: 24,
          bottom: 48,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: scheme.inverseSurface.withValues(alpha: 0.88), borderRadius: BorderRadius.circular(16)),
            child: Text(_msg ?? widget.hint, textAlign: TextAlign.center, style: TextStyle(color: scheme.onInverseSurface)),
          ),
        ),
      ]),
    );
  }
}
