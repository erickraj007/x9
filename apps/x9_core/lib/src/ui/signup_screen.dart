import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../session.dart';
import '../signup_api.dart';
import '../signup_validators.dart';
import 'logo.dart';
import 'otp_boxes.dart';
import 'theme.dart';
import 'widgets.dart';

/// Self sign-up: (1) details + location, (2) WhatsApp code, (3) [onSignedIn] with the `/auth/signup/verify` answer.
/// See docs/SIGNUP-KYC-VIP-UPI-V6.md section 1.
///
/// * [locate] returns the phone location, or null when it could not be read. It may throw an
///   [Exception] with a readable message (permission denied, GPS off); that message is shown.
/// * [onSignedIn] saves the login and moves on (the app's root gate then shows the lock setup).
/// * [onBack] runs when the person leaves from the first step (default: pop the screen).
/// v6.10: what the phone's position resolves to (Blinkit-style): a readable address, the pin code and the city.
typedef SignupPlace = ({String address, String pincode, String city});

class SignupScreen extends StatefulWidget {
  const SignupScreen({
    super.key,
    required this.role,
    required this.locate,
    required this.onSignedIn,
    this.onBack,
    this.initialMobile,
    this.reverseGeocode,
  });

  /// v6.10: turns the GPS fix into an address + pin code + city (user app passes the `geocoding` package here).
  final Future<SignupPlace?> Function(double lat, double lng)? reverseGeocode;

  final SignupRole role;
  final Future<({double lat, double lng})?> Function() locate;
  final Future<void> Function(Map<String, dynamic> authResponse) onSignedIn;
  final VoidCallback? onBack;

  /// Pre-filled mobile (e.g. from a failed sign-in).
  final String? initialMobile;

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _mobile = TextEditingController(text: SignupValidators.mobile(widget.initialMobile ?? '') ?? '');
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _pincode = TextEditingController();
  final _aadhaar = TextEditingController();
  final _landmark = TextEditingController();
  final _referral = TextEditingController();
  String _city = '';
  DateTime? _dob;
  final _pan = TextEditingController();
  final _bankAccount = TextEditingController();
  final _ifsc = TextEditingController();
  final _holder = TextEditingController();
  final _shop = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _code = TextEditingController();

  int _step = 0;
  bool _busy = false;
  bool _locating = false;
  bool _showOptional = false;
  ({double lat, double lng})? _loc;
  String? _locError;
  String? _banner;
  String? _otpError;
  SignupOtpInfo _otp = const SignupOtpInfo();
  Timer? _timer;
  int _left = 0;

  /// v6.9 (user app): occupation and yearly income, used to show similar offers.
  String? _occupation;
  String? _income;
  static const _occupations = <(String, String)>[
    ('SALARY', 'Salary'),
    ('FREELANCE', 'Freelance'),
    ('SMALL_BUSINESS', 'Small business'),
    ('ENTREPRENEUR', 'Entrepreneur'),
  ];
  static const _incomes = <(String, String)>[
    ('UPTO_3L', 'Up to ₹3 lakhs'),
    ('UPTO_10L', 'Up to ₹10 lakhs'),
    ('UPTO_1CR', 'Up to ₹1 crore'),
    ('ABOVE_1CR', 'Above ₹1 crore'),
  ];

  bool get _merchant => widget.role == SignupRole.merchant;

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in [_mobile, _name, _email, _address, _pincode, _aadhaar, _landmark, _referral, _pan, _bankAccount, _ifsc, _holder, _shop, _password, _confirm, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _mobileValue => SignupValidators.mobile(_mobile.text) ?? _mobile.text.trim();

  void _back() {
    if (_step == 1) {
      setState(() {
        _step = 0;
        _otpError = null;
        _code.clear();
      });
      return;
    }
    final cb = widget.onBack;
    if (cb != null) {
      cb();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _useLocation() async {
    if (_locating) return;
    setState(() {
      _locating = true;
      _locError = null;
    });
    try {
      final r = await widget.locate();
      SignupPlace? place;
      if (r != null && widget.reverseGeocode != null) {
        try {
          place = await widget.reverseGeocode!(r.lat, r.lng);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _locating = false;
        _loc = r;
        if (place != null) {
          // The home address is filled from the GPS fix; the person can still edit it.
          if (place.address.isNotEmpty) _address.text = place.address;
          if (place.pincode.isNotEmpty) _pincode.text = place.pincode;
          _city = place.city;
        }
        if (r == null) _locError = 'Could not read your location. Turn on location, allow permission and try again.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _locating = false;
        _locError = signupErrorMessage(e);
      });
    }
  }

  Future<void> _sendCode() async {
    if (_busy) return;
    final formOk = _form.currentState?.validate() ?? false;
    final hasLoc = _loc != null;
    setState(() {
      _banner = formOk ? null : 'Please correct the highlighted fields.';
      if (!hasLoc) _locError = 'Tap "Set location". Your location is needed to create the account.';
    });
    if (!formOk || !hasLoc) return;
    setState(() => _busy = true);
    try {
      final info = await SignupApi.requestOtp(_mobileValue, widget.role);
      if (!mounted) return;
      _code.clear();
      setState(() {
        _otp = info;
        _step = 1;
        _busy = false;
        _otpError = null;
      });
      _startTimer(info.resendIn);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _banner = signupErrorMessage(e);
      });
    }
  }

  void _startTimer(int seconds) {
    _timer?.cancel();
    _left = seconds > 0 ? seconds : 30;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _left--);
      if (_left <= 0) t.cancel();
    });
  }

  Future<void> _resend() async {
    if (_busy) return;
    try {
      final info = await SignupApi.requestOtp(_mobileValue, widget.role);
      if (!mounted) return;
      _code.clear();
      setState(() {
        _otp = info;
        _otpError = null;
      });
      _startTimer(info.resendIn);
      showOk(context, 'Code sent again on WhatsApp');
    } catch (e) {
      if (mounted) showError(context, signupErrorMessage(e));
    }
  }

  Map<String, dynamic> _fields() {
    final f = <String, dynamic>{
      'role': widget.role.wire,
      'otp': _code.text,
      'name': _name.text.trim(),
      'mobile': _mobileValue,
      'email': _email.text.trim(),
      'address': _address.text.trim(),
      'pincode': _pincode.text.trim(),
      'lat': _loc!.lat,
      'lng': _loc!.lng,
      if (_dob != null) 'dob': '${_dob!.year.toString().padLeft(4, '0')}-${_dob!.month.toString().padLeft(2, '0')}-${_dob!.day.toString().padLeft(2, '0')}',
      if (_city.isNotEmpty) 'city': _city,
      if (_landmark.text.trim().isNotEmpty) 'landmark': _landmark.text.trim(),
      if (!_merchant && _referral.text.trim().isNotEmpty) 'referral_code': _referral.text.trim().toUpperCase(),
    };
    void opt(String key, String? value) {
      if (value != null && value.isNotEmpty) f[key] = value;
    }

    opt('aadhaar_number', SignupValidators.aadhaar(_aadhaar.text));
    opt('pan_number', SignupValidators.pan(_pan.text));
    opt('bank_account_number', SignupValidators.bankAccount(_bankAccount.text));
    opt('bank_ifsc', SignupValidators.ifsc(_ifsc.text));
    opt('bank_holder', _holder.text.trim());
    opt('password', _password.text); // v6.14: every new account (user and merchant) creates its password here
    if (_merchant) {
      opt('shop_name', _shop.text.trim());
    } else {
      opt('occupation', _occupation);
      opt('annual_income', _income);
    }
    opt('device_id', SessionStore.instance.deviceId);
    return f;
  }

  Future<void> _verify() async {
    if (_busy || _code.text.length != _otp.length || _loc == null) return;
    setState(() {
      _busy = true;
      _otpError = null;
    });
    try {
      final resp = await SignupApi.verify(_fields());
      await widget.onSignedIn(resp);
      if (mounted) setState(() => _busy = false);
    } catch (e) {
      if (!mounted) return;
      final code = e is ApiException ? e.code : null;
      if (code == 'MOBILE_TAKEN') {
        setState(() {
          _busy = false;
          _step = 0;
          _banner = signupErrorMessage(e);
        });
        return;
      }
      setState(() {
        _busy = false;
        _otpError = signupErrorMessage(e);
        if (code == 'OTP_INVALID' || code == 'OTP_LOCKED' || code == 'OTP_EXPIRED') _code.clear();
      });
    }
  }

  // ----- fields -----

  InputDecoration _dec(String label, {IconData? icon, String? helper, String? prefix}) =>
      InputDecoration(labelText: label, helperText: helper, prefixText: prefix, prefixIcon: icon == null ? null : Icon(icon), helperMaxLines: 3);

  Widget _gap([double h = 12]) => SizedBox(height: h);

  Widget _detailsStep(BuildContext context) {
    final p = context.x9;
    return Form(
      key: _form,
      autovalidateMode: AutovalidateMode.disabled,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(_merchant ? 'Create your shop account' : 'Create your X9 account', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 6),
        Text(
          'Fields marked * are required. We will verify your mobile number with a code on WhatsApp.',
          style: TextStyle(color: p.textSecondary, height: 1.4),
        ),
        if (_banner != null) ...[
          const SizedBox(height: 14),
          _Notice(text: _banner!, color: X9Colors.error, icon: Icons.error_outline_rounded),
        ],
        const SizedBox(height: 18),
        if (_merchant) ...[
          TextFormField(
            controller: _shop,
            textCapitalization: TextCapitalization.words,
            decoration: _dec('Shop name *', icon: Icons.storefront_rounded),
            validator: (v) => SignupValidators.nameOk(v ?? '') ? null : 'Enter your shop name',
          ),
          _gap(),
        ],
        TextFormField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.name],
          decoration: _dec(_merchant ? 'Owner name *' : 'Full name *', icon: Icons.person_outline_rounded),
          validator: (v) => SignupValidators.nameOk(v ?? '') ? null : 'Enter your full name',
        ),
        _gap(),
        TextFormField(
          controller: _mobile,
          keyboardType: TextInputType.phone,
          maxLength: 10,
          autofillHints: const [AutofillHints.telephoneNumberNational],
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: _dec('Mobile number (WhatsApp) *', icon: Icons.phone_iphone_rounded, prefix: '+91  ').copyWith(counterText: ''),
          validator: (v) => SignupValidators.mobile(v ?? '') == null ? 'Enter a valid 10-digit mobile number' : null,
        ),
        _gap(),
        TextFormField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: _dec('E-mail *', icon: Icons.alternate_email_rounded),
          validator: (v) => SignupValidators.email(v ?? '') == null ? 'Enter a valid e-mail address' : null,
        ),
        _gap(),
        FormField<DateTime>(
          validator: (_) => (!_merchant && _dob == null) ? 'Select your date of birth' : null,
          builder: (st) => InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () async {
              final now = DateTime.now();
              final d = await showDatePicker(
                context: context,
                initialDate: _dob ?? DateTime(now.year - 25, now.month, now.day),
                firstDate: DateTime(1900),
                lastDate: DateTime(now.year - 10, now.month, now.day),
                helpText: 'Date of birth',
              );
              if (d != null) {
                setState(() => _dob = d);
                st.didChange(d);
              }
            },
            child: InputDecorator(
              decoration: _dec(_merchant ? 'Date of birth' : 'Date of birth *', icon: Icons.cake_outlined).copyWith(errorText: st.errorText),
              child: Text(
                _dob == null ? 'DD / MM / YYYY' : '${_dob!.day.toString().padLeft(2, '0')} / ${_dob!.month.toString().padLeft(2, '0')} / ${_dob!.year}',
                style: TextStyle(color: _dob == null ? context.x9.textSecondary : null),
              ),
            ),
          ),
        ),
        if (!_merchant) ...[
          _gap(),
          TextFormField(
            controller: _aadhaar,
            keyboardType: TextInputType.number,
            maxLength: 12,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: _dec('Aadhaar card number *', icon: Icons.badge_outlined).copyWith(counterText: ''),
            validator: (v) => SignupValidators.aadhaar(v ?? '') != null ? null : 'Aadhaar must be 12 digits',
          ),
          _gap(),
          DropdownButtonFormField<String>(
            value: _occupation,
            isExpanded: true,
            decoration: _dec('Occupation *', icon: Icons.work_outline_rounded),
            items: [for (final o in _occupations) DropdownMenuItem(value: o.$1, child: Text(o.$2))],
            onChanged: (v) => setState(() => _occupation = v),
            validator: (v) => v == null ? 'Select your occupation' : null,
          ),
          _gap(),
          DropdownButtonFormField<String>(
            value: _income,
            isExpanded: true,
            decoration: _dec('Annual income *', icon: Icons.account_balance_wallet_outlined),
            items: [for (final o in _incomes) DropdownMenuItem(value: o.$1, child: Text(o.$2))],
            onChanged: (v) => setState(() => _income = v),
            validator: (v) => v == null ? 'Select your yearly income range' : null,
          ),
        ],
        _gap(),
        TextFormField(
          controller: _address,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          keyboardType: TextInputType.streetAddress,
          decoration: _dec('Home address * (tap Set location to fill it)', icon: Icons.home_outlined),
          validator: (v) => (v ?? '').trim().length < 8 ? 'Set your location or type your full home address' : null,
        ),
        _gap(),
        TextFormField(
          controller: _pincode,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: _dec('Pin code (or your living city pin code) *', icon: Icons.pin_drop_outlined).copyWith(counterText: ''),
          validator: (v) => SignupValidators.pincode(v ?? '') == null ? 'Enter the 6-digit pin code' : null,
        ),
        if (!_merchant) ...[
          _gap(),
          TextFormField(
            controller: _landmark,
            maxLength: 120,
            decoration: _dec('Flat / landmark (optional)', icon: Icons.flag_outlined).copyWith(counterText: ''),
          ),
          _gap(),
          TextFormField(
            controller: _referral,
            maxLength: 12,
            textCapitalization: TextCapitalization.characters,
            decoration: _dec('Sales team referral code (optional)', icon: Icons.card_giftcard_rounded).copyWith(counterText: ''),
          ),
        ],
        _gap(),
        _locationCard(context),
        ...[
          _gap(18),
          TextFormField(
            controller: _password,
            obscureText: true,
            autofillHints: const [AutofillHints.newPassword],
            decoration: _dec('Password *', icon: Icons.lock_outline_rounded, helper: 'At least 8 characters'),
            validator: (v) => SignupValidators.passwordOk(v ?? '') ? null : 'Use at least 8 characters',
          ),
          _gap(),
          TextFormField(
            controller: _confirm,
            obscureText: true,
            decoration: _dec('Confirm password *', icon: Icons.lock_outline_rounded),
            validator: (v) => (v ?? '') == _password.text ? null : 'Passwords do not match',
          ),
        ],
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _showOptional = !_showOptional),
            icon: Icon(_showOptional ? Icons.remove_rounded : Icons.add_rounded, size: 18),
            label: Text(_showOptional ? 'Hide optional details' : 'Add optional details (Aadhaar, PAN, bank)'),
          ),
        ),
        if (_showOptional) ..._optionalFields(),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _busy ? null : _sendCode,
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
              : const Icon(Icons.chat_rounded),
          label: const Text('Send code on WhatsApp'),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: _back, child: const Text('I already have an account')),
      ]),
    );
  }

  List<Widget> _optionalFields() => [
        _gap(4),
        if (_merchant) TextFormField(
          controller: _aadhaar,
          keyboardType: TextInputType.number,
          maxLength: 12,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: _dec('Aadhaar number (optional)', icon: Icons.badge_outlined).copyWith(counterText: ''),
          validator: (v) => (v ?? '').trim().isEmpty || SignupValidators.aadhaar(v!) != null ? null : 'Aadhaar must be 12 digits',
        ),
        _gap(),
        TextFormField(
          controller: _pan,
          maxLength: 10,
          textCapitalization: TextCapitalization.characters,
          decoration: _dec('PAN (optional)', icon: Icons.credit_card_outlined).copyWith(counterText: ''),
          validator: (v) => (v ?? '').trim().isEmpty || SignupValidators.pan(v!) != null ? null : 'Enter a valid PAN, e.g. ABCDE1234F',
        ),
        _gap(),
        TextFormField(
          controller: _bankAccount,
          keyboardType: TextInputType.number,
          maxLength: 18,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: _dec('Bank account number (optional)', icon: Icons.account_balance_outlined).copyWith(counterText: ''),
          validator: (v) => (v ?? '').trim().isEmpty || SignupValidators.bankAccount(v!) != null ? null : 'Enter 9 to 18 digits',
        ),
        _gap(),
        TextFormField(
          controller: _ifsc,
          maxLength: 11,
          textCapitalization: TextCapitalization.characters,
          decoration: _dec('IFSC (optional)', icon: Icons.numbers_rounded).copyWith(counterText: ''),
          validator: (v) {
            final t = (v ?? '').trim();
            if (t.isEmpty) return _bankAccount.text.trim().isEmpty ? null : 'IFSC is needed with the account number';
            return SignupValidators.ifsc(t) != null ? null : 'Enter a valid IFSC, e.g. HDFC0001234';
          },
        ),
        _gap(),
        TextFormField(
          controller: _holder,
          textCapitalization: TextCapitalization.words,
          decoration: _dec('Account holder name (optional)', icon: Icons.person_pin_outlined),
          validator: (v) => (v ?? '').trim().isEmpty && _bankAccount.text.trim().isNotEmpty ? 'Holder name is needed with the account number' : null,
        ),
      ];

  Widget _locationCard(BuildContext context) {
    final p = context.x9;
    final loc = _loc;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _locError != null ? X9Colors.error : p.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(loc == null ? Icons.my_location_rounded : Icons.check_circle_rounded, color: loc == null ? X9Colors.primary : X9Colors.success, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              loc == null
                  ? 'Set location *'
                  : (_city.isNotEmpty ? 'Location set: $_city' : 'Location set: ${loc.lat.toStringAsFixed(5)}, ${loc.lng.toStringAsFixed(5)}'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          'Uses your phone\'s location to write your home address. It is saved as your delivery address for orders.',
          style: TextStyle(color: p.textSecondary, fontSize: 12.5, height: 1.35),
        ),
        if (_locError != null) ...[
          const SizedBox(height: 8),
          Text(_locError!, style: TextStyle(color: p.statusText(X9Colors.error), fontSize: 12.5, height: 1.35)),
        ],
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _locating ? null : _useLocation,
          icon: _locating
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.gps_fixed_rounded, size: 18),
          label: Text(loc == null ? 'Set location' : 'Update location'),
        ),
      ]),
    );
  }

  Widget _otpStep(BuildContext context) {
    final p = context.x9;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Verify on WhatsApp', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 8),
      Text.rich(
        TextSpan(children: [
          const TextSpan(text: 'We sent a code to WhatsApp '),
          TextSpan(text: SignupValidators.display(_mobileValue), style: TextStyle(fontWeight: FontWeight.w600, color: p.text)),
        ]),
        style: TextStyle(color: p.textSecondary, height: 1.4),
      ),
      const SizedBox(height: 26),
      X9OtpBoxes(
        length: _otp.length,
        controller: _code,
        autofocus: true,
        onCompleted: (_) => _verify(),
      ),
      if (_otpError != null) ...[
        const SizedBox(height: 14),
        _Notice(text: _otpError!, color: X9Colors.error, icon: Icons.error_outline_rounded),
      ],
      const SizedBox(height: 20),
      Center(
        child: _left > 0
            ? Text('Resend code in 0:${_left.toString().padLeft(2, '0')}', style: TextStyle(color: p.textSecondary, fontWeight: FontWeight.w600))
            : TextButton.icon(onPressed: _busy ? null : _resend, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Resend code')),
      ),
      const SizedBox(height: 18),
      ListenableBuilder(
        listenable: _code,
        builder: (context, _) => FilledButton(
          onPressed: !_busy && _code.text.length == _otp.length ? _verify : null,
          child: _busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
              : const Text('Verify & create account'),
        ),
      ),
      const SizedBox(height: 8),
      TextButton(onPressed: _busy ? null : _back, child: const Text('Change details or number')),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == 0 && widget.onBack == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: _back),
          title: Text(_step == 0 ? 'Sign up' : 'Verify mobile'),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              const Center(child: X9Logo(height: 72)),
              const SizedBox(height: 14),
              _step == 0 ? _detailsStep(context) : _otpStep(context),
            ],
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.color, required this.icon});
  final String text;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: context.x9.statusText(color), height: 1.35, fontWeight: FontWeight.w600))),
        ]),
      );
}
