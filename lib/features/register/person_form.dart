import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/option_picker.dart';
import '../../core/options.dart';
import '../../core/widgets.dart';

/// Holds the values of the person details form (used by Register and by the Attendance screen).
class PersonFormController extends ChangeNotifier {
  final name = TextEditingController();
  final college = OptionController();
  final branch = OptionController();
  final pg = OptionController();
  final skills = MultiOptionController();
  final interests = MultiOptionController();
  final chanting = TextEditingController();
  final comments = TextEditingController();
  String gender = '', level = '', occupation = '', stay = '', feedback = '';

  /// The FOLK guide's ID ('' = the default guide; the server gives new people the default one).
  String guideId = '';

  /// Date of birth "YYYY-MM-DD" ('' = not given) and, for people entered before it was asked, the age typed back then.
  String dob = '';
  int oldAge = 0;

  void load(Person? p) {
    name.text = p?.name ?? '';
    college.set(Opt(p?.collegeId ?? '', p?.profession ?? ''));
    branch.set(Opt(p?.branchId ?? '', p?.branch ?? ''));
    pg.set(Opt(p?.pgId ?? '', p?.pgName ?? ''));
    guideId = p?.guideId ?? '';
    gender = p?.gender ?? '';
    level = p?.level ?? '';
    occupation = p?.occupation ?? '';
    dob = p?.dob ?? '';
    oldAge = (p?.dob ?? '').isEmpty ? (p?.age ?? 0) : 0;
    skills.values = p?.skillList ?? const [];
    interests.values = p?.interestList ?? const [];
    chanting.text = (p?.chantingRounds ?? 0) > 0 ? '${p!.chantingRounds}' : '';
    comments.text = p?.comments ?? '';
    stay = p?.currentStay ?? '';
    feedback = p?.feedback ?? '';
    notifyListeners();
  }

  void clear() => load(null);

  void set({String? gender, String? level, String? occupation, String? stay, String? feedback, String? guideId, String? dob}) {
    this.dob = dob ?? this.dob;
    this.guideId = guideId ?? this.guideId;
    this.stay = stay ?? this.stay;
    this.feedback = feedback ?? this.feedback;
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
    ..._picked(college, 'college_id', 'profession'),
    ..._picked(branch, 'branch_id', 'branch'),
    ..._picked(pg, 'pg_id', 'pg_name'),
    if (guideId.isNotEmpty) 'guide_id': guideId,
    'dob': dob,
    if (int.tryParse(chanting.text.trim()) != null) 'chanting_rounds': int.parse(chanting.text.trim()),
    'current_stay': stay,
    'feedback': feedback,
    'skill_ids': [for (final o in skills.values) o.id],
    'interest_ids': [for (final o in interests.values) o.id],
    'comments': comments.text.trim(),
  };

  /// A value picked from the list is sent by ID. Text typed without tapping Add is sent as text: the server matches it or adds it.
  static Map<String, dynamic> _picked(OptionController c, String idKey, String textKey) {
    final o = c.opt;
    if (o.id.isNotEmpty) return {idKey: o.id};
    if (o.title.isNotEmpty) return {textKey: o.title};
    return {idKey: ''};
  }

  @override
  void dispose() {
    name.dispose();
    college.dispose();
    branch.dispose();
    pg.dispose();
    skills.dispose();
    interests.dispose();
    chanting.dispose();
    comments.dispose();
    super.dispose();
  }
}

class PersonFields extends ConsumerWidget {
  const PersonFields({super.key, required this.form, required this.boot, this.requireLevel = true});
  final PersonFormController form;
  final Bootstrap? boot;
  final bool requireLevel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final opts = ref.watch(optionsProvider).value ?? const OptionLists();
    Future<Opt?> Function(String) add(OptionList l) =>
        (t) => addOption(context, ref, l, t);
    return ListenableBuilder(
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
          OptionPicker(
            controller: form.college,
            label: 'Company / College',
            icon: Icons.apartment_outlined,
            options: opts[OptionList.college],
            onAdd: add(OptionList.college),
          ),
          OptionPicker(
            controller: form.branch,
            label: 'Branch',
            icon: Icons.account_tree_outlined,
            options: opts[OptionList.branch],
            onAdd: add(OptionList.branch),
          ),
          OptionPicker(
            controller: form.pg,
            label: 'PG / Residence',
            icon: Icons.home_outlined,
            options: opts[OptionList.pg],
            onAdd: add(OptionList.pg),
          ),
          GuideDropdown(
            guides: opts.guides,
            value: form.guideId.isEmpty ? (opts.defaultGuide?.id ?? '') : form.guideId,
            onChanged: (v) => form.set(guideId: v),
          ),
          DateOfBirthField(
            value: form.dob,
            oldAge: form.oldAge,
            onChanged: (v) => form.set(dob: v),
          ),
          OptionDropdown(
            label: 'Staying',
            value: form.stay,
            options: boot?.stays ?? const ['With Parents', 'In Hostel'],
            icon: Icons.bed_outlined,
            onChanged: (v) => form.set(stay: v),
          ),
          MultiOptionPicker(
            controller: form.skills,
            label: 'Skills',
            icon: Icons.star_outline,
            options: opts[OptionList.skill],
            onAdd: add(OptionList.skill),
          ),
          MultiOptionPicker(
            controller: form.interests,
            label: 'Interests',
            icon: Icons.favorite_border,
            options: opts[OptionList.interest],
            onAdd: add(OptionList.interest),
          ),
          TextFormField(
            controller: form.chanting,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
            decoration: const InputDecoration(labelText: 'Chanting rounds', prefixIcon: Icon(Icons.self_improvement_outlined)),
          ),
          OptionDropdown(
            label: 'Feedback',
            value: form.feedback,
            options: boot?.feedbacks ?? const ['Excellent', 'Good'],
            icon: Icons.thumb_up_alt_outlined,
            onChanged: (v) => form.set(feedback: v),
          ),
          TextFormField(
            controller: form.comments,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Comments', prefixIcon: Icon(Icons.notes_outlined)),
          ),
        ],
      ),
    );
  }
}

/// FOLK Guide: picked from the guides set up in ERPNext (no Add button). The guide's phone comes with the guide.
class GuideDropdown extends StatelessWidget {
  const GuideDropdown({super.key, required this.guides, required this.value, required this.onChanged});
  final List<Guide> guides;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => OptionDropdown(
    label: 'FOLK Guide',
    value: value,
    options: [for (final g in guides) g.id],
    labelOf: (id) => guides.firstWhere((g) => g.id == id, orElse: () => Guide(id, id)).title,
    allowNone: false,
    icon: Icons.supervisor_account_outlined,
    onChanged: onChanged,
  );
}

/// Whole years from [dob] ("YYYY-MM-DD") to [today].
int ageFrom(String dob, DateTime today) {
  final d = DateTime.tryParse(dob);
  if (d == null) return 0;
  final had = today.month > d.month || (today.month == d.month && today.day >= d.day);
  return today.year - d.year - (had ? 0 : 1);
}

/// Date of birth, picked from a calendar; the age is shown next to it. For someone entered before dates of birth were asked,
/// the age typed back then is shown until a date is picked.
class DateOfBirthField extends StatelessWidget {
  const DateOfBirthField({super.key, required this.value, required this.onChanged, this.oldAge = 0});
  final String value;
  final int oldAge;
  final ValueChanged<String> onChanged;

  static String _two(int n) => n.toString().padLeft(2, '0');

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(value) ?? DateTime(now.year - 20, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      helpText: 'Date of birth',
    );
    if (d != null) onChanged('${d.year}-${_two(d.month)}-${_two(d.day)}');
  }

  @override
  Widget build(BuildContext context) {
    final d = DateTime.tryParse(value);
    final shown = d == null ? '' : '${_two(d.day)}-${_two(d.month)}-${d.year}';
    final helper = d != null
        ? 'Age ${ageFrom(value, DateTime.now())}'
        : oldAge > 0
        ? 'Age $oldAge (typed earlier). Add the date of birth.'
        : null;
    return InkWell(
      onTap: () => _pick(context),
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        isEmpty: shown.isEmpty,
        decoration: InputDecoration(
          labelText: 'Date of birth',
          helperText: helper,
          prefixIcon: const Icon(Icons.cake_outlined),
          suffixIcon: shown.isEmpty
              ? const Icon(Icons.calendar_month_outlined)
              : IconButton(tooltip: 'Clear', icon: const Icon(Icons.close), onPressed: () => onChanged('')),
        ),
        child: Text(shown),
      ),
    );
  }
}
