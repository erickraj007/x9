import 'package:flutter/material.dart';
import 'package:x9_core/x9_core.dart';

import '../../state/app_state.dart';
import '../../util/helpers.dart';
import '../../widgets/otp_boxes.dart';

/// Registers this phone's payment-approval key (POST /app/device-key). Needs the X9 MPIN once;
/// a new user first creates an MPIN (POST /auth/mpin/otp → POST /auth/mpin {mpin, otp}).
class DeviceSetupScreen extends StatefulWidget {
  const DeviceSetupScreen({super.key, required this.hasMpin, required this.onDone});
  final bool hasMpin;
  final VoidCallback onDone;

  @override
  State<DeviceSetupScreen> createState() => _DeviceSetupScreenState();
}

enum _Step { enter, create, confirm, otp }

class _DeviceSetupScreenState extends State<DeviceSetupScreen> {
  late _Step _step = widget.hasMpin ? _Step.enter : _Step.create;
  String? _newMpin;
  String? _error;
  bool _busy = false;
  final _otp = TextEditingController();
  int _otpLen = 6;

  static const _weak = {'0000', '1111', '1234', '4321', '9999'};

  @override
  void dispose() {
    _otp.dispose();
    super.dispose();
  }

  Future<void> _register(String mpin) async {
    final key = await SessionStore.instance.createDeviceKey();
    try {
      await Api.instance.post('/app/device-key', {'device_id': SessionStore.instance.deviceId, 'device_key': key, 'mpin': mpin});
    } catch (_) {
      await SessionStore.instance.deleteDeviceKey();
      rethrow;
    }
  }

  Future<void> _entered(String pin) async {
    if (_busy) return;
    switch (_step) {
      case _Step.enter:
        setState(() {
          _busy = true;
          _error = null;
        });
        try {
          await _register(pin);
          if (mounted) widget.onDone();
        } catch (e) {
          if (mounted) {
            setState(() {
              _busy = false;
              _error = e is ApiException && (e.code ?? '').contains('MPIN') ? 'Wrong MPIN. Try again.' : friendlyError(e);
            });
          }
        }
        break;
      case _Step.create:
        if (_weak.contains(pin)) {
          setState(() => _error = 'Too easy to guess. Choose another MPIN.');
          return;
        }
        setState(() {
          _newMpin = pin;
          _step = _Step.confirm;
          _error = null;
        });
        break;
      case _Step.confirm:
        if (pin != _newMpin) {
          setState(() {
            _newMpin = null;
            _step = _Step.create;
            _error = 'MPINs did not match. Start again.';
          });
          return;
        }
        _saveMpin();
        break;
      case _Step.otp:
        break;
    }
  }

  /// v6.2: the first MPIN right after sign-in / sign-up needs NO second code (one confirmation only).
  /// When the server does want the WhatsApp code (changing an existing MPIN, old session) the code step is shown.
  Future<void> _saveMpin() async {
    final mpin = _newMpin;
    if (mpin == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.instance.post('/auth/mpin', {'mpin': mpin});
      await _register(mpin);
      if (mounted) widget.onDone();
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.code == 'MPIN_OTP_REQUIRED') {
        setState(() {
          _busy = false;
          _step = _Step.otp;
        });
        _sendOtp();
        return;
      }
      setState(() {
        _busy = false;
        _error = friendlyError(e);
      });
    }
  }

  Future<void> _sendOtp() async {
    try {
      final r = asMap(await Api.instance.post('/auth/mpin/otp'));
      final n = asInt(r['length']);
      if (mounted && n > 0) setState(() => _otpLen = n);
    } catch (e) {
      if (mounted) showFriendlyError(context, e);
    }
  }

  Future<void> _verifyOtp() async {
    final mpin = _newMpin;
    if (mpin == null) return;
    if (_otp.text.length < 4) throw Exception('Enter the WhatsApp code.');
    await Api.instance.post('/auth/mpin', {'mpin': mpin, 'otp': _otp.text});
    await _register(mpin);
    if (mounted) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final mobile = fmtMobile(str(SessionStore.instance.user?['mobile']));
    final title = switch (_step) {
      _Step.enter => 'Approve this phone',
      _Step.create => 'Create your X9 MPIN',
      _Step.confirm => 'Confirm your MPIN',
      _Step.otp => 'Confirm on WhatsApp',
    };
    final subtitle = switch (_step) {
      _Step.enter => 'Enter your 4-digit X9 MPIN to sign in on this phone. Day to day the app opens with your phone lock (pattern, fingerprint or face); payments need the MPIN and a WhatsApp code.',
      _Step.create => 'Choose a 4-digit MPIN. You set it once, and use it for wallet and bank payments and when you sign in again.',
      _Step.confirm => 'Enter the same MPIN again.',
      _Step.otp => 'Code sent on WhatsApp to your mobile${mobile.isEmpty ? '' : ' $mobile'}.',
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('Phone setup'),
        automaticallyImplyLeading: false,
        actions: [TextButton(onPressed: () => AppState.instance.signOut(), child: const Text('Sign out'))],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(gradient: X9Colors.heroGradient, shape: BoxShape.circle),
                child: Icon(_step == _Step.otp ? Icons.sms_rounded : Icons.phonelink_lock_rounded, color: Colors.white, size: 34),
              ),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: context.x9.textSecondary, height: 1.4)),
              const SizedBox(height: 24),
              if (_step == _Step.otp) ...[
                OtpBoxes(length: _otpLen, controller: _otp, autofocus: true),
                const SizedBox(height: 14),
                ResendTimer(onResend: () => Api.instance.post('/auth/mpin/otp')),
                const SizedBox(height: 18),
                BusyButton(label: 'Verify & finish', icon: Icons.verified_rounded, onPressed: _verifyOtp),
                TextButton(
                  onPressed: () => setState(() {
                    _step = _Step.create;
                    _newMpin = null;
                  }),
                  child: const Text('Change MPIN'),
                ),
              ] else if (_busy)
                const Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator())
              else
                PinPad(key: ValueKey(_step), length: 4, onCompleted: _entered, error: _error),
            ]),
          ),
        ),
      ),
    );
  }
}
