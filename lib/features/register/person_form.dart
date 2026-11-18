import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models.dart';
import '../../core/widgets.dart';

/// Holds the values of the person details form (used by Register and by the Attendance screen).
class PersonFormController extends ChangeNotifier {
  final name = TextEditingController();
  final profession = TextEditingController();
  final pgName = TextEditingController();
  final venue = TextEditingController();
  final gmap = TextEditingController();
  final callNo = TextEditingController();
  final fgName = TextEditingController();
  final fgMob = TextEditingController();
  String gender = '', level = '', occupation = '';

  void load(Person? p) {
    name.text = p?.name ?? '';
    profession.text = p?.profession ?? '';
    pgName.text = p?.pgName ?? '';
    venue.text = p?.venue ?? '';
    gmap.text = p?.gmapLink ?? '';
    callNo.text = p?.callNo ?? '';
    fgName.text = p?.fgName ?? '';
    fgMob.text = p?.fgMob ?? '';
    gender = p?.gender ?? '';
    level = p?.level ?? '';
    occupation = p?.occupation ?? '';
    notifyListeners();
  }

  void clear() => load(null);

  void set({String? gender, String? level, String? occupation}) {
    this.gender = gender ?? this.gender;
    this.level = level ?? this.level;
    this.occupation = occupation ?? this.occupation;
    notifyListeners();
  }

  Map<String, dynamic> toJson() => {
    'name': name.text.trim(),
    'gender': gender,
    'level': level,
    'occupation': occupation,
    'profession': profession.text.trim(),
    'pg_name': pgName.text.trim(),
    'venue': venue.text.trim(),
    'gmap_link': gmap.text.trim(),
    'call_no': callNo.text.trim(),
    'fg_name': fgName.text.trim(),
    'fg_mob': fgMob.text.trim(),
  };

  @override
  void dispose() {
    name.dispose();
    profession.dispose();
    pgName.dispose();
    venue.dispose();
    gmap.dispose();
    callNo.dispose();
    fgName.dispose();
    fgMob.dispose();
    super.dispose();
  }
}

final _digits = [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ \-]')), LengthLimitingTextInputFormatter(15)];

class PersonFields extends StatelessWidget {
  const PersonFields({super.key, required this.form, required this.boot, this.requireLevel = true});
  final PersonFormController form;
  final Bootstrap? boot;
  final bool requireLevel;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: form,
    builder: (context, _) => FieldGrid(
      children: [
        TextFormField(
          controller: form.name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline)),
          validator: (v) => (v ?? '').trim().isEmpty ? 'Enter the name' : null,
        ),
        OptionDropdown(
          label: 'Gender',
          value: form.gender,
          options: boot?.genders ?? const ['M', 'F'],
          labelOf: genderLabel,
          icon: Icons.wc_outlined,
          onChanged: (v) => form.set(gender: v),
        ),
        DropdownButtonFormField<String>(
          key: ValueKey('level-${form.level}'),
          initialValue: (boot?.levels ?? const ['Folk Foundation', 'Folk Prelims']).contains(form.level) ? form.level : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: requireLevel ? 'Level *' : 'Level', prefixIcon: const Icon(Icons.school_outlined)),
          items: [
            for (final l in boot?.levels ?? const ['Folk Foundation', 'Folk Prelims']) DropdownMenuItem(value: l, child: Text(l)),
          ],
          onChanged: (v) => form.set(level: v ?? ''),
          validator: (v) => requireLevel && (v == null || v.isEmpty) ? 'Choose a level' : null,
        ),
        OptionDropdown(
          label: 'Occupation',
          value: form.occupation,
          options: boot?.occupations ?? const ['Student', 'Job Search', 'Working'],
          icon: Icons.work_outline,
          onChanged: (v) => form.set(occupation: v),
        ),
        TextFormField(
          controller: form.profession,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Company / College', prefixIcon: Icon(Icons.apartment_outlined)),
        ),
        TextFormField(
          controller: form.pgName,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'PG / Residence', prefixIcon: Icon(Icons.home_outlined)),
        ),
        TextFormField(
          controller: form.venue,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Venue', prefixIcon: Icon(Icons.place_outlined)),
        ),
        TextFormField(
          controller: form.gmap,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(labelText: 'Google Map link', prefixIcon: Icon(Icons.map_outlined)),
        ),
        TextFormField(
          controller: form.callNo,
          keyboardType: TextInputType.phone,
          inputFormatters: _digits,
          decoration: const InputDecoration(labelText: 'Call number', prefixIcon: Icon(Icons.call_outlined)),
        ),
        TextFormField(
          controller: form.fgName,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'FOLK Guide name', prefixIcon: Icon(Icons.supervisor_account_outlined)),
        ),
        TextFormField(
          controller: form.fgMob,
          keyboardType: TextInputType.phone,
          inputFormatters: _digits,
          decoration: const InputDecoration(labelText: 'FOLK Guide mobile', prefixIcon: Icon(Icons.phone_outlined)),
        ),
      ],
    ),
  );
}
