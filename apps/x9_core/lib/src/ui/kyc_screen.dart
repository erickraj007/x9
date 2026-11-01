import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../kyc_api.dart';
import '../signup_validators.dart';
import 'theme.dart';
import 'widgets.dart';

/// Lets the app choose a photo for a KYC document: returns the local file path, or null when cancelled.
/// [camera] true = take a photo, false = pick from the gallery. The app supplies this (it owns the image picker).
typedef KycImagePicker = Future<String?> Function(bool camera);

Widget _statusPill(BuildContext context, String status) {
  final p = context.x9;
  late Color c;
  late IconData icon;
  switch (status) {
    case 'VERIFIED':
      c = X9Colors.success;
      icon = Icons.verified_rounded;
      break;
    case 'SUBMITTED':
      c = X9Colors.warning;
      icon = Icons.schedule_rounded;
      break;
    case 'REJECTED':
      c = X9Colors.error;
      icon = Icons.cancel_rounded;
      break;
    default:
      c = p.textSecondary;
      icon = Icons.info_outline_rounded;
  }
  final fg = c == p.textSecondary ? c : p.statusText(c);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 16, color: c),
      const SizedBox(width: 6),
      Text(kycStatusLabel(status), style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 13)),
    ]),
  );
}

/// KYC status and (when allowed) the submission form: `GET /app/kyc`, `POST /app/kyc` (multipart).
class UserKycScreen extends StatefulWidget {
  const UserKycScreen({super.key, required this.pickImage, this.onChanged});

  final KycImagePicker pickImage;

  /// Called with every status the screen loads (apps use it to refresh their cached KYC state).
  final ValueChanged<KycInfo>? onChanged;

  @override
  State<UserKycScreen> createState() => _UserKycScreenState();
}

class _UserKycScreenState extends State<UserKycScreen> {
  KycInfo? _info;
  Object? _error;
  bool _loading = true;
  bool _busy = false;

  final _form = GlobalKey<FormState>();
  final _panNo = TextEditingController();
  final _aadhaarNo = TextEditingController();
  final _bankAccount = TextEditingController();
  final _ifsc = TextEditingController();
  final _holder = TextEditingController();

  String? _pan;
  String? _aadhaarFront;
  String? _aadhaarBack;
  String? _photo;
  String? _cheque;
  String? _fileError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _panNo.dispose();
    _aadhaarNo.dispose();
    _bankAccount.dispose();
    _ifsc.dispose();
    _holder.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await KycApi.status();
      if (!mounted) return;
      setState(() {
        _info = r;
        _loading = false;
      });
      widget.onChanged?.call(r);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<bool?> _askSource() => showModalBottomSheet<bool>(
        context: context,
        builder: (c) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(leading: const Icon(Icons.photo_camera_rounded), title: const Text('Take a photo'), onTap: () => Navigator.pop(c, true)),
            ListTile(leading: const Icon(Icons.photo_library_rounded), title: const Text('Choose from gallery'), onTap: () => Navigator.pop(c, false)),
          ]),
        ),
      );

  Future<void> _pick(String slot) async {
    final bool? camera = slot == 'photo' ? true : await _askSource();
    if (camera == null || !mounted) return;
    try {
      final path = await widget.pickImage(camera);
      if (path == null || !mounted) return;
      setState(() {
        switch (slot) {
          case 'pan':
            _pan = path;
            break;
          case 'aadhaar_front':
            _aadhaarFront = path;
            break;
          case 'aadhaar_back':
            _aadhaarBack = path;
            break;
          case 'photo':
            _photo = path;
            break;
          default:
            _cheque = path;
        }
        _fileError = null;
      });
    } catch (_) {
      if (mounted) showError(context, 'Could not open the camera or gallery. Check the app permissions and try again.');
    }
  }

  void _clear(String slot) {
    setState(() {
      switch (slot) {
        case 'pan':
          _pan = null;
          break;
        case 'aadhaar_front':
          _aadhaarFront = null;
          break;
        case 'aadhaar_back':
          _aadhaarBack = null;
          break;
        case 'photo':
          _photo = null;
          break;
        default:
          _cheque = null;
      }
    });
  }

  /// Name of the first file that is missing or too big, else null.
  String? _fileProblem() {
    final mandatory = <String, String?>{'PAN card': _pan, 'Aadhaar front': _aadhaarFront, 'Selfie photo': _photo};
    for (final e in mandatory.entries) {
      if (e.value == null) return '${e.key} is required.';
    }
    final all = <String, String?>{
      'PAN card': _pan,
      'Aadhaar front': _aadhaarFront,
      'Aadhaar back': _aadhaarBack,
      'Selfie photo': _photo,
      'Cancelled cheque': _cheque,
    };
    for (final e in all.entries) {
      final path = e.value;
      if (path == null) continue;
      try {
        if (File(path).lengthSync() > kycMaxFileBytes) return '${e.key} is larger than 5 MB. Choose a smaller photo.';
      } catch (_) {
        return '${e.key} could not be read. Choose it again.';
      }
    }
    return null;
  }

  Future<void> _submit() async {
    if (_busy) return;
    final formOk = _form.currentState?.validate() ?? false;
    final problem = _fileProblem();
    setState(() => _fileError = problem);
    if (!formOk || problem != null) return;
    setState(() => _busy = true);
    try {
      final files = <String, ApiFile>{
        'pan': ApiFile(_pan!),
        'aadhaar_front': ApiFile(_aadhaarFront!),
        'photo': ApiFile(_photo!),
        if (_aadhaarBack != null) 'aadhaar_back': ApiFile(_aadhaarBack!),
        if (_cheque != null) 'cancelled_cheque': ApiFile(_cheque!),
      };
      final fields = <String, String>{
        'pan_number': SignupValidators.pan(_panNo.text) ?? _panNo.text.trim().toUpperCase(),
        'aadhaar_number': SignupValidators.aadhaar(_aadhaarNo.text) ?? _aadhaarNo.text.trim(),
        if (_bankAccount.text.trim().isNotEmpty) 'bank_account_number': SignupValidators.bankAccount(_bankAccount.text) ?? _bankAccount.text.trim(),
        if (_ifsc.text.trim().isNotEmpty) 'bank_ifsc': SignupValidators.ifsc(_ifsc.text) ?? _ifsc.text.trim().toUpperCase(),
        if (_holder.text.trim().isNotEmpty) 'bank_holder': _holder.text.trim(),
      };
      await KycApi.submit(files: files, fields: fields);
      if (!mounted) return;
      showOk(context, 'KYC submitted. We will verify it shortly.');
      setState(() => _busy = false);
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('KYC verification')),
      body: SafeArea(child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading && _info == null) return const Center(child: CircularProgressIndicator());
    if (_info == null) return ErrorRetry(message: _error is ApiException ? (_error! as ApiException).display : '$_error', onRetry: _load);
    final info = _info!;
    final p = context.x9;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          Row(children: [
            Expanded(child: Text('Your KYC', style: Theme.of(context).textTheme.titleLarge)),
            _statusPill(context, info.status),
          ]),
          const SizedBox(height: 8),
          Text(
            'KYC is needed to use the X9 wallet, prepaid card and banking. Browsing shops and offers works without it.',
            style: TextStyle(color: p.textSecondary, height: 1.4),
          ),
          if (info.status == 'REJECTED') ...[
            const SizedBox(height: 14),
            _note(context, info.remarks.isEmpty ? 'Your KYC was rejected. Please submit it again with clear documents.' : 'Rejected: ${info.remarks}', X9Colors.error, Icons.cancel_rounded),
          ],
          if (info.status == 'SUBMITTED') ...[
            const SizedBox(height: 14),
            _note(context, 'Your documents are with our team. You will get a message when they are verified.', X9Colors.warning, Icons.schedule_rounded),
          ],
          if (info.verified) ...[
            const SizedBox(height: 14),
            _note(context, 'You are verified. Wallet, prepaid card and banking are open to you.', X9Colors.success, Icons.verified_rounded),
          ],
          if (!info.canSubmit) ..._summary(context, info),
          if (info.canSubmit) ..._formFields(context),
        ],
      ),
    );
  }

  Widget _note(BuildContext context, String text, Color color, IconData icon) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: context.x9.statusText(color), height: 1.35, fontWeight: FontWeight.w600))),
        ]),
      );

  List<Widget> _summary(BuildContext context, KycInfo info) {
    final rows = <MapEntry<String, String>>[];
    void add(String label, dynamic v) {
      final t = (v ?? '').toString();
      if (t.isNotEmpty) rows.add(MapEntry(label, t));
    }

    add('Aadhaar', info.profile['aadhaar_masked']);
    add('PAN', info.profile['pan_masked']);
    add('Bank account', info.profile['bank_masked']);
    if (rows.isEmpty && info.documents.isEmpty) return const [];
    return [
      const SizedBox(height: 16),
      Card(
        child: Column(children: [
          for (final r in rows) ListTile(dense: true, title: Text(r.key), trailing: Text(r.value, style: const TextStyle(fontWeight: FontWeight.w600))),
          for (final d in info.documents)
            ListTile(
              dense: true,
              leading: const Icon(Icons.description_outlined),
              title: Text((d['label'] ?? d['type'] ?? d['name'] ?? 'Document').toString().replaceAll('_', ' ')),
              trailing: d['status'] == null ? null : Text(d['status'].toString().replaceAll('_', ' '), style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
        ]),
      ),
    ];
  }

  List<Widget> _formFields(BuildContext context) {
    final p = context.x9;
    return [
      const SizedBox(height: 18),
      Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextFormField(
            controller: _panNo,
            maxLength: 10,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'PAN number *', prefixIcon: Icon(Icons.credit_card_outlined), counterText: ''),
            validator: (v) => SignupValidators.pan(v ?? '') == null ? 'Enter a valid PAN, e.g. ABCDE1234F' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _aadhaarNo,
            keyboardType: TextInputType.number,
            maxLength: 12,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Aadhaar number *', prefixIcon: Icon(Icons.badge_outlined), counterText: ''),
            validator: (v) => SignupValidators.aadhaar(v ?? '') == null ? 'Aadhaar must be 12 digits' : null,
          ),
          const SizedBox(height: 18),
          Text('Documents (JPG or PNG, up to 5 MB each)', style: TextStyle(color: p.textSecondary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _DocTile(label: 'PAN card *', icon: Icons.credit_card_rounded, path: _pan, onPick: () => _pick('pan'), onClear: () => _clear('pan')),
          _DocTile(label: 'Aadhaar front *', icon: Icons.badge_rounded, path: _aadhaarFront, onPick: () => _pick('aadhaar_front'), onClear: () => _clear('aadhaar_front')),
          _DocTile(label: 'Aadhaar back (optional)', icon: Icons.badge_outlined, path: _aadhaarBack, onPick: () => _pick('aadhaar_back'), onClear: () => _clear('aadhaar_back')),
          _DocTile(label: 'Selfie photo *', icon: Icons.face_rounded, path: _photo, onPick: () => _pick('photo'), onClear: () => _clear('photo')),
          if (_fileError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Text(_fileError!, style: TextStyle(color: p.statusText(X9Colors.error), fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 14),
          Text('Bank details (optional)', style: TextStyle(color: p.textSecondary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextFormField(
            controller: _bankAccount,
            keyboardType: TextInputType.number,
            maxLength: 18,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Bank account number', prefixIcon: Icon(Icons.account_balance_outlined), counterText: ''),
            validator: (v) => (v ?? '').trim().isEmpty || SignupValidators.bankAccount(v!) != null ? null : 'Enter 9 to 18 digits',
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _ifsc,
            maxLength: 11,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'IFSC', prefixIcon: Icon(Icons.numbers_rounded), counterText: ''),
            validator: (v) {
              final t = (v ?? '').trim();
              if (t.isEmpty) return _bankAccount.text.trim().isEmpty ? null : 'IFSC is needed with the account number';
              return SignupValidators.ifsc(t) != null ? null : 'Enter a valid IFSC, e.g. HDFC0001234';
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _holder,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Account holder name', prefixIcon: Icon(Icons.person_pin_outlined)),
            validator: (v) => (v ?? '').trim().isEmpty && _bankAccount.text.trim().isNotEmpty ? 'Holder name is needed with the account number' : null,
          ),
          const SizedBox(height: 12),
          _DocTile(label: 'Cancelled cheque (optional)', icon: Icons.receipt_long_rounded, path: _cheque, onPick: () => _pick('cheque'), onClear: () => _clear('cheque')),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                : const Icon(Icons.upload_rounded),
            label: Text(_busy ? 'Uploading...' : 'Submit for verification'),
          ),
          const SizedBox(height: 8),
          Text(
            'Your documents are sent over a secure connection and stored encrypted.',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.textSecondary, fontSize: 12),
          ),
        ]),
      ),
    ];
  }
}

class _DocTile extends StatelessWidget {
  const _DocTile({required this.label, required this.icon, required this.path, required this.onPick, required this.onClear});
  final String label;
  final IconData icon;
  final String? path;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final p = context.x9;
    final chosen = path;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.border)),
      child: ListTile(
        onTap: onPick,
        leading: chosen == null
            ? Icon(icon, color: X9Colors.primary)
            : ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(chosen),
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.description_rounded, color: X9Colors.primary),
                ),
              ),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(chosen == null ? 'Tap to add' : 'Added - tap to change', style: TextStyle(color: chosen == null ? p.textSecondary : p.statusText(X9Colors.success))),
        trailing: chosen == null
            ? const Icon(Icons.add_a_photo_rounded)
            : IconButton(icon: const Icon(Icons.close_rounded), tooltip: 'Remove', onPressed: onClear),
      ),
    );
  }
}

/// "Complete KYC to use wallet, prepaid card and banking" banner with a button that opens [UserKycScreen].
/// Show it where a KYC_REQUIRED answer would otherwise leave a dead end, or call [KycGate.show] for a dialog.
class KycGate extends StatelessWidget {
  const KycGate({super.key, required this.pickImage, this.onChanged, this.message = defaultMessage});

  static const String defaultMessage = 'Complete KYC to use wallet, prepaid card and banking';

  final KycImagePicker pickImage;
  final ValueChanged<KycInfo>? onChanged;
  final String message;

  /// Dialog version. Opens [UserKycScreen] when the person taps "Complete KYC".
  static Future<void> show(BuildContext context, {required KycImagePicker pickImage, ValueChanged<KycInfo>? onChanged, String message = defaultMessage}) async {
    final nav = Navigator.of(context);
    final go = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        icon: const Icon(Icons.verified_user_rounded, color: X9Colors.primary, size: 40),
        title: const Text('KYC required'),
        content: Text(message, textAlign: TextAlign.center),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Later')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Complete KYC')),
        ],
      ),
    );
    if (go == true) {
      await nav.push<void>(MaterialPageRoute<void>(builder: (_) => UserKycScreen(pickImage: pickImage, onChanged: onChanged)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.x9;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: p.primarySoft, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        const Icon(Icons.verified_user_rounded, color: X9Colors.primary, size: 28),
        const SizedBox(width: 12),
        Expanded(child: Text(message, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.3))),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => UserKycScreen(pickImage: pickImage, onChanged: onChanged))),
          child: const Text('Complete KYC'),
        ),
      ]),
    );
  }
}
