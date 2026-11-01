import 'package:flutter/material.dart';
import 'package:x9_core/x9_core.dart';

import '../../util/helpers.dart';

/// First sign-in "Life style" form (optional). Why we ask: we share similar offers with you.
/// Also reachable later from the side bar (Life style). Everything is optional; Skip is always available.
class LifestyleScreen extends StatefulWidget {
  const LifestyleScreen({super.key, this.firstTime = false});
  final bool firstTime;

  @override
  State<LifestyleScreen> createState() => _LifestyleScreenState();
}

class _Routine {
  _Routine({this.time, String program = ''}) : program = TextEditingController(text: program);
  TimeOfDay? time;
  final TextEditingController program;
}

class _LifestyleScreenState extends State<LifestyleScreen> {
  static const _maxRoutines = 11; // 1 + "add 10 more"
  static const _marital = {'SINGLE': 'Single', 'MARRIED': 'Married', 'DIVORCED': 'Divorced', 'WIDOWED': 'Widowed'};
  static const _morning = {
    'CYCLING': 'Cycling', 'JOGGING': 'Jogging', 'SWIMMING': 'Swimming', 'GYM': 'Gym',
    'TREADMILL': 'Treadmill', 'WALKING': 'Walking', 'YOGA': 'Yoga', 'MEDITATION': 'Meditation',
  };
  static const _pets = {'DOG': 'Dog', 'CAT': 'Cat', 'BIRD': 'Birds', 'OTHER': 'Others'};
  static const _food = {'VEG': 'Veg', 'NON_VEG': 'Non-veg', 'VEGAN': 'Vegan'};
  static const _loved = {
    'FATHER': 'Father', 'MOTHER': 'Mother', 'WIFE': 'Wife', 'HUSBAND': 'Husband',
    'DAUGHTER': 'Daughter', 'SON': 'Son', 'FRIEND': 'Friend', 'BESTIE': 'Bestie',
  };
  static const _occupations = {
    'PRIVATE_EMPLOYEE': 'Private employee', 'GOVERNMENT_EMPLOYEE': 'Government employee', 'FREELANCER': 'Freelancer',
    'BUSINESS': 'Business', 'ENTREPRENEUR': 'Entrepreneur', 'POLITICIAN': 'Politician',
  };
  static const _incomes = {'UPTO_3L': 'Up to ₹3 lakhs', 'UPTO_10L': 'Up to ₹10 lakhs', 'UPTO_1CR': 'Up to ₹1 crore', 'ABOVE_1CR': 'Above ₹1 crore'};

  /// Admin-editable choice lists from the server ({list: {code: label}}); the built-in maps above are the fallback.
  final Map<String, Map<String, String>> _items = {};
  Map<String, String> _opt(String key, Map<String, String> fallback) {
    final m = _items[key];
    return m == null || m.isEmpty ? fallback : m;
  }

  bool _loading = true;
  bool _busy = false;
  Object? _error;

  String? _marit;
  String? _foodPref;
  String? _lovedOne;
  String? _occupation;
  String? _income;
  final Set<String> _morningSel = {};
  final Set<String> _petSel = {};
  bool _hasCar = false;
  bool _hasBike = false;
  final _t = <String, TextEditingController>{
    for (final k in ['morning_other', 'pet_other', 'car_brand', 'car_model', 'bike_brand', 'bike_model', 'food_notes', 'fav_places', 'fav_phone', 'fav_channel', 'fav_hero', 'fav_heroine'])
      k: TextEditingController(),
  };
  final List<_Routine> _am = [_Routine()];
  final List<_Routine> _pm = [_Routine()];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _t.values) {
      c.dispose();
    }
    for (final r in [..._am, ..._pm]) {
      r.program.dispose();
    }
    super.dispose();
  }

  TimeOfDay? _parse(String s) {
    final p = s.split(':');
    if (p.length != 2) return null;
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    return h == null || m == null ? null : TimeOfDay(hour: h, minute: m);
  }

  String _fmt(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    try {
      final r = asMap(await Api.instance.get('/app/lifestyle'));
      final d = asMap(r['data']);
      final oi = asMap(r['option_items']);
      if (!mounted) return;
      setState(() {
        for (final e in oi.entries) {
          final m = <String, String>{};
          for (final it in asList(e.value)) {
            final x = asMap(it);
            if (str(x['code']).isNotEmpty) m[str(x['code'])] = str(x['label'], str(x['code']));
          }
          _items[e.key] = m;
        }
        _occupation = str(r['occupation']).isEmpty ? null : str(r['occupation']);
        _income = str(r['annual_income']).isEmpty ? null : str(r['annual_income']);
        _marit = str(d['marital_status']).isEmpty ? null : str(d['marital_status']);
        _foodPref = str(d['food_pref']).isEmpty ? null : str(d['food_pref']);
        _lovedOne = str(d['loved_one']).isEmpty ? null : str(d['loved_one']);
        _morningSel
          ..clear()
          ..addAll(asList(d['morning_activities']).map((e) => '$e'));
        _petSel
          ..clear()
          ..addAll(asList(d['pets']).map((e) => '$e'));
        _hasCar = str(d['car_brand']).isNotEmpty;
        _hasBike = str(d['bike_brand']).isNotEmpty;
        for (final e in _t.entries) {
          e.value.text = str(d[e.key]);
        }
        final routines = asMap(r['routines']);
        void fill(List<_Routine> into, dynamic rows) {
          final list = asList(rows).map(asMap).toList();
          if (list.isEmpty) return;
          into
            ..clear()
            ..addAll([for (final x in list) _Routine(time: _parse(str(x['at'])), program: str(x['program']))]);
        }

        fill(_am, routines['MORNING']);
        fill(_pm, routines['EVENING']);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  List<Map<String, String>> _routineBody(List<_Routine> rows) => [
        for (final r in rows)
          if (r.time != null && r.program.text.trim().isNotEmpty) {'at': _fmt(r.time!), 'program': r.program.text.trim()},
      ];

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      String? v(String k) => _t[k]!.text.trim().isEmpty ? null : _t[k]!.text.trim();
      await Api.instance.put('/app/lifestyle', {
        if (_occupation != null) 'occupation': _occupation,
        if (_income != null) 'annual_income': _income,
        if (_marit != null) 'marital_status': _marit,
        if (_foodPref != null) 'food_pref': _foodPref,
        if (_lovedOne != null) 'loved_one': _lovedOne,
        'morning_activities': _morningSel.toList(),
        'pets': _petSel.toList(),
        'has_car': _hasCar,
        'has_bike': _hasBike,
        for (final k in _t.keys)
          if (v(k) != null && !((k.startsWith('car_') && !_hasCar) || (k.startsWith('bike_') && !_hasBike))) k: v(k),
        'routines': {'MORNING': _routineBody(_am), 'EVENING': _routineBody(_pm)},
      });
      if (!mounted) return;
      showOk(context, 'Saved. We will show you similar offers.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showFriendlyError(context, e);
      }
    }
  }

  Future<void> _skip() async {
    setState(() => _busy = true);
    try {
      if (widget.firstTime) await Api.instance.post('/app/lifestyle/skip', {});
    } catch (_) {}
    if (mounted) Navigator.of(context).pop(false);
  }

  // ---- small builders
  Widget _title(String t, {String? sub}) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          if (sub != null) Text(sub, style: TextStyle(color: context.x9.textSecondary, fontSize: 12.5)),
        ]),
      );

  Widget _single(Map<String, String> opts, String? value, void Function(String?) set) => Wrap(spacing: 8, runSpacing: 4, children: [
        for (final e in opts.entries)
          ChoiceChip(label: Text(e.value), selected: value == e.key, onSelected: (s) => setState(() => set(s ? e.key : null))),
      ]);

  Widget _multi(Map<String, String> opts, Set<String> sel) => Wrap(spacing: 8, runSpacing: 4, children: [
        for (final e in opts.entries)
          FilterChip(
            label: Text(e.value),
            selected: sel.contains(e.key),
            onSelected: (s) => setState(() => s ? sel.add(e.key) : sel.remove(e.key)),
          ),
      ]);

  Widget _field(String key, String label, {IconData? icon}) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: TextField(controller: _t[key], maxLength: 120, decoration: InputDecoration(labelText: label, counterText: '', prefixIcon: icon == null ? null : Icon(icon))),
      );

  Widget _routines(String label, List<_Routine> rows, String defaultTime) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < rows.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            // The app theme makes buttons full-width; inside a Row that gives infinite width and the whole row vanished
            // (no time button, no text box, no keyboard). A fixed width keeps the row laid out.
            SizedBox(
              width: 104,
              child: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52), padding: const EdgeInsets.symmetric(horizontal: 8)),
              onPressed: () async {
                final t = await showTimePicker(context: context, initialTime: rows[i].time ?? _parse(defaultTime)!);
                if (t != null) setState(() => rows[i].time = t);
              },
              child: Text(rows[i].time == null ? 'Time' : rows[i].time!.format(context)),
            )),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: rows[i].program, maxLength: 120, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(hintText: 'Program (e.g. yoga, walk, prayer)', counterText: ''))),
            IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.close_rounded),
              onPressed: rows.length <= 1 && rows[i].time == null && rows[i].program.text.isEmpty
                  ? null
                  : () => setState(() {
                        rows[i].program.dispose();
                        rows.removeAt(i);
                        if (rows.isEmpty) rows.add(_Routine());
                      }),
            ),
          ]),
        ),
      if (rows.length < _maxRoutines)
        TextButton.icon(onPressed: () => setState(() => rows.add(_Routine())), icon: const Icon(Icons.add_rounded), label: Text('Add another $label time & program')),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.firstTime,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Life style'),
          automaticallyImplyLeading: !widget.firstTime,
          actions: [TextButton(onPressed: _busy ? null : _skip, child: const Text('Skip'))],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ErrorRetry(message: friendlyError(_error!), onRetry: () {
                    setState(() {
                      _loading = true;
                      _error = null;
                    });
                    _load();
                  })
                : ListView(keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, padding: EdgeInsets.fromLTRB(18, 8, 18, 40 + MediaQuery.of(context).viewInsets.bottom), children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: context.x9.primarySoft, borderRadius: BorderRadius.circular(14)),
                      child: const Text('Why we ask this: we share similar offers with you. Everything here is optional.', style: TextStyle(height: 1.4)),
                    ),
                    _title('Occupation'),
                    _single(_opt('occupations', _occupations), _occupation, (v) => _occupation = v),
                    _title('Annual income'),
                    _single(_opt('incomes', _incomes), _income, (v) => _income = v),
                    _title('Marital status'),
                    _single(_opt('marital_status', _marital), _marit, (v) => _marit = v),
                    _title('In the morning', sub: 'Select what you do'),
                    _multi(_opt('morning_activities', _morning), _morningSel),
                    _field('morning_other', 'Something else (type)'),
                    _title('Do you have pets?'),
                    _multi(_opt('pets', _pets), _petSel),
                    if (_petSel.contains('OTHER')) _field('pet_other', 'Which pet? (type)'),
                    _title('Vehicles'),
                    SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('I have a car'), value: _hasCar, onChanged: (v) => setState(() => _hasCar = v)),
                    if (_hasCar) ...[_field('car_brand', 'Car brand'), _field('car_model', 'Car model')],
                    SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('I have a two-wheeler'), value: _hasBike, onChanged: (v) => setState(() => _hasBike = v)),
                    if (_hasBike) ...[_field('bike_brand', 'Two-wheeler brand'), _field('bike_model', 'Two-wheeler model')],
                    _title('Food'),
                    _single(_opt('food_pref', _food), _foodPref, (v) => _foodPref = v),
                    _field('food_notes', 'Favourite food (type)'),
                    _title('Favourites', sub: 'Type your answer'),
                    _field('fav_places', 'Favourite tour places', icon: Icons.landscape_rounded),
                    _field('fav_phone', 'Favourite mobile phone', icon: Icons.smartphone_rounded),
                    _field('fav_channel', 'Favourite channel', icon: Icons.tv_rounded),
                    _field('fav_hero', 'Favourite hero', icon: Icons.person_rounded),
                    _field('fav_heroine', 'Favourite heroine', icon: Icons.person_outline_rounded),
                    _title('Who is your lovable person?'),
                    _single(_opt('loved_one', _loved), _lovedOne, (v) => _lovedOne = v),
                    _title('Morning schedule', sub: 'Select the time and add the program, e.g. 4:30 AM. Add up to 10 more.'),
                    _routines('morning', _am, '04:30'),
                    _title('Evening schedule', sub: 'Select the time and add the program, e.g. 5:00 PM. Add up to 10 more.'),
                    _routines('evening', _pm, '17:00'),
                    const SizedBox(height: 24),
                    FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving…' : 'Save')),
                  ]),
      ),
    );
  }
}
