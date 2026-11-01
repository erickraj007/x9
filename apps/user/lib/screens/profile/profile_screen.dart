import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:x9_core/x9_core.dart';

import '../../state/app_state.dart';
import '../../state/kyc_state.dart';
import '../../util/helpers.dart';
import '../../widgets/otp_boxes.dart';
import '../../widgets/skeleton.dart';
import '../kyc/kyc_entry.dart';
import '../vip/vip_screen.dart';

/// Merge a profile response (`{user:{...}}` or the user itself) into the stored session user.
Future<Map<String, dynamic>> saveProfileUser(dynamic response) async {
  final r = asMap(response);
  final u = asMap(r['user']).isNotEmpty ? asMap(r['user']) : r;
  final merged = <String, dynamic>{...?SessionStore.instance.user, ...u};
  await SessionStore.instance.saveUser(merged);
  AppState.instance.signedInUserChanged();
  return merged;
}

/// Profile: name, mobile, e-mail, Google link state.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _p;
  Object? _error;

  @override
  void initState() {
    super.initState();
    KycState.instance.load();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = asMap(await Api.instance.get('/app/profile'));
      await saveProfileUser(r);
      if (mounted) {
        setState(() {
          _p = r;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Map<String, dynamic> get _user => asMap(_p?['user']).isNotEmpty ? asMap(_p?['user']) : (SessionStore.instance.user ?? const <String, dynamic>{});

  Future<void> _editName() async {
    final ctrl = TextEditingController(text: str(_user['name']));
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(c).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Your name', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          TextField(controller: ctrl, autofocus: true, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Full name')),
          const SizedBox(height: 14),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('Save')),
        ]),
      ),
    );
    if (name == null || name.length < 2 || !mounted) return;
    try {
      final r = await withProgress(context, () => Api.instance.put('/app/profile', {'name': name}));
      await saveProfileUser(r);
      if (!mounted) return;
      showOk(context, 'Name updated');
      _load();
    } catch (e) {
      if (mounted) showFriendlyError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = _user;
    final name = str(u['name'], 'X9 user');
    final vip = asBool(u['is_vip']);
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: _p == null && _error == null
          ? const SkeletonList(count: 4)
          : _p == null
              ? ErrorRetry(message: friendlyError(_error!), onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(gradient: X9Colors.heroGradient, borderRadius: BorderRadius.circular(24)),
                      child: Row(children: [
                        Container(
                          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2.5)),
                          child: ClipOval(
                            child: SizedBox(
                              width: 64,
                              height: 64,
                              child: NetImage(
                                str(u['avatar_url']),
                                placeholder: Container(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  alignment: Alignment.center,
                                  child: Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w600)),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
                            Text(fmtMobile(str(u['mobile'])), style: const TextStyle(color: Colors.white70)),
                            if (vip) ...[
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
                                child: const Text('VIP MEMBER', style: TextStyle(color: X9Colors.primaryDark, fontWeight: FontWeight.w600, fontSize: 11, letterSpacing: 1)),
                              ),
                            ],
                          ]),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Column(children: [
                        ListTile(
                          leading: const Icon(Icons.person_rounded, color: X9Colors.primary),
                          title: const Text('Name'),
                          subtitle: Text(name),
                          trailing: const Icon(Icons.edit_rounded, size: 20),
                          onTap: _editName,
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.phone_iphone_rounded, color: X9Colors.primary),
                          title: const Text('Mobile number'),
                          subtitle: Text(fmtMobile(str(u['mobile']))),
                          trailing: const Text('Change', style: TextStyle(color: X9Colors.primary, fontWeight: FontWeight.w700)),
                          onTap: () async {
                            final changed = await go<bool>(context, const ChangeContactScreen(email: false));
                            if (changed == true) _load();
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.alternate_email_rounded, color: X9Colors.primary),
                          title: const Text('E-mail'),
                          subtitle: Text(str(u['email'], 'Not added')),
                          trailing: Text(str(u['email']).isEmpty ? 'Add' : 'Change', style: const TextStyle(color: X9Colors.primary, fontWeight: FontWeight.w700)),
                          onTap: () async {
                            final changed = await go<bool>(context, const ChangeContactScreen(email: true));
                            if (changed == true) _load();
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.g_mobiledata_rounded, color: X9Colors.primary, size: 30),
                          title: const Text('Google account'),
                          subtitle: Text(asBool(u['google_linked']) ? 'Linked — you can sign in with Google' : 'Not linked'),
                          trailing: Icon(
                            asBool(u['google_linked']) ? Icons.check_circle_rounded : Icons.link_off_rounded,
                            color: asBool(u['google_linked']) ? X9Colors.success : context.x9.textSecondary,
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Column(children: [
                        ListenableBuilder(
                          listenable: KycState.instance,
                          builder: (context, _) => ListTile(
                            leading: const Icon(Icons.verified_user_rounded, color: X9Colors.primary),
                            title: const Text('KYC verification'),
                            subtitle: Text(KycState.instance.label),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => openKyc(context),
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.workspace_premium_rounded, color: X9Colors.primary),
                          title: const Text('X9 VIP Club'),
                          subtitle: Text(vip ? 'You are a VIP member' : 'Join for VIP offers and a VIP card'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => go(context, const VipScreen()),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: ListTile(
                        leading: Icon(asBool(_p!['device_registered']) ? Icons.phonelink_lock_rounded : Icons.phonelink_erase_rounded,
                            color: asBool(_p!['device_registered']) ? X9Colors.success : X9Colors.error),
                        title: const Text('This phone'),
                        subtitle: Text(asBool(_p!['device_registered']) ? 'Approved for payments' : 'Not approved for payments'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Card(child: ThemeModeSelector()),
                  ]),
                ),
    );
  }
}

/// Change mobile (SMS OTP, 5 digits) or e-mail (e-mail OTP, 6 digits).
class ChangeContactScreen extends StatefulWidget {
  const ChangeContactScreen({super.key, required this.email});
  final bool email;

  @override
  State<ChangeContactScreen> createState() => _ChangeContactScreenState();
}

class _ChangeContactScreenState extends State<ChangeContactScreen> {
  final _value = TextEditingController();
  final _otp = TextEditingController();
  bool _sent = false;

  int get _otpLen => widget.email ? 6 : 5;

  @override
  void dispose() {
    _value.dispose();
    _otp.dispose();
    super.dispose();
  }

  String get _v => _value.text.trim();

  Future<void> _send() async {
    if (widget.email) {
      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_v)) throw Exception('Enter a valid e-mail address.');
    } else {
      if (!RegExp(r'^[6-9]\d{9}$').hasMatch(_v)) throw Exception('Enter a valid 10-digit mobile number.');
    }
    await Api.instance.post('/app/profile/contact/otp', widget.email ? {'email': _v} : {'mobile': _v});
    if (mounted) setState(() => _sent = true);
  }

  Future<void> _verify() async {
    if (_otp.text.length != _otpLen) throw Exception('Enter the $_otpLen-digit OTP.');
    final r = await Api.instance.post(
      '/app/profile/contact',
      widget.email ? {'email': _v, 'email_otp': _otp.text} : {'mobile': _v, 'mobile_otp': _otp.text},
    );
    await saveProfileUser(r);
    if (!mounted) return;
    showOk(context, widget.email ? 'E-mail updated' : 'Mobile number updated');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final what = widget.email ? 'e-mail' : 'mobile number';
    return Scaffold(
      appBar: AppBar(title: Text(widget.email ? 'Change e-mail' : 'Change mobile')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(_sent ? 'Enter the OTP' : 'New $what', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 6),
        Text(
          _sent ? 'OTP sent to ${widget.email ? _v : '+91 $_v'}' : 'We will send an OTP to verify it.',
          style: TextStyle(color: context.x9.textSecondary),
        ),
        const SizedBox(height: 24),
        if (!_sent) ...[
          TextField(
            controller: _value,
            autofocus: true,
            keyboardType: widget.email ? TextInputType.emailAddress : TextInputType.phone,
            maxLength: widget.email ? 190 : 10,
            inputFormatters: widget.email ? null : [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: widget.email ? 'E-mail address' : 'Mobile number',
              prefixText: widget.email ? null : '+91  ',
              counterText: '',
            ),
          ),
          const SizedBox(height: 20),
          BusyButton(label: 'Send OTP', icon: Icons.sms_rounded, onPressed: _send),
        ] else ...[
          OtpBoxes(length: _otpLen, controller: _otp, autofocus: true),
          const SizedBox(height: 16),
          Center(child: ResendTimer(onResend: _send)),
          const SizedBox(height: 16),
          BusyButton(label: 'Verify & update', icon: Icons.verified_rounded, onPressed: _verify),
          TextButton(onPressed: () => setState(() => _sent = false), child: Text('Change $what')),
        ],
      ]),
    );
  }
}
