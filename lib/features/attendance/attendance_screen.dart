import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:async';
import 'dart:math' show Random;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/cache.dart';
import '../../core/config.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import '../printing/printer_service.dart';
import '../printing/printer_status.dart';
import '../printing/printer_sheet.dart';
import '../printing/receipt_format.dart';
import '../printing/receipt_renderer.dart';
import '../register/person_form.dart';
import 'attendance_repo.dart';
import '../../core/layout.dart';

final todayProvider = StreamProvider.autoDispose.family<List<AttendanceItem>, String>(
  (ref, event) => cachedGet(
    ref,
    '/attendance/today',
    (r) => ((r['items'] as List?) ?? const []).map((e) => AttendanceItem.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
    query: {'event': event},
  ),
);

/// Who was marked on an earlier day ("YYYY-MM-DD") for an event.
final dayProvider = StreamProvider.autoDispose.family<List<AttendanceItem>, ({String event, String date})>(
  (ref, k) => cachedGet(
    ref,
    '/attendance/today',
    (r) => ((r['items'] as List?) ?? const []).map((e) => AttendanceItem.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
    query: {'event': k.event, 'date': k.date},
  ),
);

String _isoDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});
  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> with WidgetsBindingObserver {
  final _search = TextEditingController();
  final _form = PersonFormController();
  final _formKey = GlobalKey<FormState>();
  Timer? _debounce, _poll;
  // Each piece of state has its own notifier, so a keystroke rebuilds only the widgets that show it (not the whole page).
  final _resultsN = ValueNotifier<List<Person>>(const []);
  final _personN = ValueNotifier<Person?>(null); // looked-up registered person
  final _newMobN = ValueNotifier<String?>(null); // a typed number that is not registered
  final _editN = ValueNotifier<bool>(false); // show every field of the looked-up person (the small edit button)
  final _dateN = ValueNotifier<DateTime?>(null); // null = today (marking allowed); another day = history, read only
  final _busyN = ValueNotifier<bool>(false);
  final _searchingN = ValueNotifier<bool>(false);
  final _offlineN = ValueNotifier<bool>(false);
  final _recent = <String, List<Person>>{}; // answers already fetched this session: re-typing is instant
  int _seq = 0;

  Person? get _person => _personN.value;
  String? get _newMob => _newMobN.value;
  bool get _offlinePerson => _offlineN.value;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Standard refresh: when the screen opens (the provider loads), when the app comes back (below), on pull-down, and after the user's own actions.
    // Plus a slow refresh while this screen is open, because several volunteers share this live list.
    _poll = Timer.periodic(kLiveListRefresh, (_) {
      final e = ref.read(selectedEventProvider);
      if (mounted && e != null && WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) ref.invalidate(todayProvider(e));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(pendingCountProvider.notifier).sync();
      final e = ref.read(selectedEventProvider);
      if (e != null) ref.invalidate(todayProvider(e));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    _poll?.cancel();
    _search.dispose();
    _form.dispose();
    for (final n in [_resultsN, _personN, _newMobN, _editN, _dateN, _busyN, _searchingN, _offlineN]) {
      n.dispose();
    }
    super.dispose();
  }

  void _reset() {
    _seq++;
    _search.clear();
    _resultsN.value = const [];
    _personN.value = null;
    _newMobN.value = null;
    _offlineN.value = false;
    _editN.value = false;
    _searchingN.value = false;
    _form.clear();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    final q = v.trim();
    if (_personN.value != null) _personN.value = null;
    if (_newMobN.value != null) _newMobN.value = null;
    if (_offlineN.value) _offlineN.value = false;
    _editN.value = false;
    if (q.length < 3) {
      _seq++;
      _searchingN.value = false;
      if (_resultsN.value.isNotEmpty) _resultsN.value = const [];
      return;
    }
    final mob = normalizeMobile(q);
    final hit = _recent[q.toLowerCase()];
    if (hit != null && mob == null) {
      _resultsN.value = hit; // instant: no waiting for the network
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 180), () => mob != null ? _lookup(mob) : _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    final id = ++_seq;
    _searchingN.value = true;
    try {
      final r = await ref.read(attendanceRepoProvider).search(q);
      if (mounted && id == _seq) {
        _recent[q.toLowerCase()] = r;
        _resultsN.value = r;
      }
    } on ApiException catch (e) {
      if (mounted && !e.isNetwork) showMessage(context, e.message, error: true);
    } finally {
      if (mounted && id == _seq) _searchingN.value = false;
    }
  }

  Future<void> _lookup(String mob) async {
    final id = ++_seq;
    _searchingN.value = true;
    _resultsN.value = const [];
    try {
      final p = await ref.read(attendanceRepoProvider).lookup(mob);
      if (!mounted || id != _seq) return;
      _form.load(p);
      _personN.value = p;
      _newMobN.value = p == null ? mob : null;
    } on ApiException catch (e) {
      if (!mounted) return;
      // Offline: a typed number can still be marked (sent later) only if an admin turned the offline queue on.
      if (e.isNetwork && (ref.read(bootstrapProvider).value?.offlineEnabled ?? false)) {
        _form.load(null);
        _offlineN.value = true;
        _personN.value = Person(mob: mob, name: '');
        showMessage(context, 'No internet. You can still mark this number; it will be sent when the signal returns.');
      } else {
        showMessage(context, e.message, error: true);
      }
    } finally {
      if (mounted && id == _seq) _searchingN.value = false;
    }
  }

  /// Marks the person present (once a day: the server says "already" for a repeat).
  /// With [print] it also prints the receipt, and if the person was already marked it only prints.
  Future<void> _mark({required bool isNew, bool print = false}) async {
    final event = ref.read(selectedEventProvider);
    final mob = _person?.mob ?? _newMob;
    if (event == null || mob == null) return;
    if (isNew && !_formKey.currentState!.validate()) return;
    _busyN.value = true;
    try {
      final f = _form.toJson();
      final label = _person?.name ?? _form.name.text.trim();
      // For a registered person: the fields on screen (the empty ones, or all after the edit button) are saved with the check-in.
      final shown = isNew || _offlinePerson ? null : _shownFields(_person!);
      final edits = shown == null ? null : _form.toJson(only: shown);
      final r = await ref
          .read(attendanceRepoProvider)
          .mark(
            mob: mob,
            event: event,
            label: label,
            edits: edits == null || edits.isEmpty ? null : edits,
            register: isNew ? f : null,
            allowQueue: ref.read(bootstrapProvider).value?.offlineEnabled ?? false,
          );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      String? printed; // what to tell the user about the receipt: printed here, sent to the printing phone, or waiting
      if (print) printed = await _printReceipt(event, mob, r, _person?.attendanceCount ?? 0);
      if (!mounted) return;
      final who = r.name.isEmpty ? mob : r.name;
      if (r.queued) {
        showMessage(context, '$who saved offline. It will be sent automatically.${printed == null ? '' : ' $printed'}');
        ref.read(pendingCountProvider.notifier).refresh();
      } else if (r.status == 'already') {
        showMessage(context, printed == null ? '$who is already marked present today.' : '$who was already marked today. $printed');
      } else {
        final base = '${r.registered ? 'Registered and marked' : 'Marked present'}: $who';
        showMessage(context, printed == null ? base : '$base. $printed');
      }
      ref.invalidate(todayProvider(event));
      ref.invalidate(printStationsProvider);
      _reset();
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) _busyN.value = false;
    }
  }

  /// Prints the receipt. If this phone is connected to the printer it prints here; otherwise the receipt goes to the shared queue and the phone
  /// that is connected to the printer prints it. Returns what to tell the user, or null if it failed (a message is shown). The check-in itself
  /// is already saved, and pressing "Mark & Print Receipt" again prints without marking twice.
  Future<String?> _printReceipt(String event, String mob, MarkResult r, int countBefore) async {
    final printer = ref.read(printerServiceProvider);
    final boot = ref.read(bootstrapProvider).value;
    var ts = r.ts;
    if (r.status == 'already') {
      // Show when they were really marked, not the time of this second tap.
      try {
        final today = await ref.read(attendanceRepoProvider).today(event);
        ts = today.where((x) => x.mob == mob).map((x) => x.ts).firstOrNull ?? ts;
      } on ApiException {
        // keep the current time
      }
    }
    final eventName = boot?.events.where((e) => e.code == event).map((e) => e.name).firstOrNull ?? event;
    final data = ReceiptData(
      name: r.name,
      mob: mob,
      event: eventName,
      ts: ts,
      // A fresh check-in adds one to the count read before marking; "already" is counted in it.
      count: r.status == 'already' ? countBefore : countBefore + 1,
      markedBy: ref.read(authProvider).value?.name ?? '',
      guide: r.guide,
      guideMobile: r.guideMobile,
    );
    if (!kIsWeb && await printer.isConnected) {
      final image = await renderReceipt(boot?.receipt ?? const ReceiptFormat(), data);
      try {
        await printer.printImage(image);
        return 'Receipt printed.';
      } on PrinterException catch (e) {
        await printer.disconnect(); // the printer is off or out of range: this phone stops being the printing phone
        if (mounted) showMessage(context, 'Could not print: ${e.message}. Press "Mark & Print Receipt" to try again.', error: true);
        return null;
      }
    }
    return _queueReceipt(data);
  }

  /// Sends the receipt to the shared queue. When no phone is connected to the printer yet, offers to connect this one: the receipt is already
  /// waiting and prints as soon as this phone connects.
  Future<String?> _queueReceipt(ReceiptData d) async {
    try {
      final res = await ref
          .read(apiProvider)
          .post(
            '/print/jobs',
            body: {
              'key':
                  '${DateTime.now().microsecondsSinceEpoch}-${d.mob}-${Random().nextInt(1 << 30)}', // one tap = one receipt, even if the request is repeated
              'name': d.name,
              'mob': d.mob,
              'event': d.event,
              'ts': d.ts,
              'count': d.count,
            },
          );
      if (((res['stations'] as num?)?.toInt() ?? 0) > 0) return 'Receipt sent to the printer.';
      if (kIsWeb || !mounted) return 'Receipt saved. It prints when a phone is connected to the printer.';
      final connected = await ensurePrinter(context, ref.read(printerServiceProvider));
      return connected ? 'Receipt sent to the printer.' : 'Receipt saved. It prints when a phone is connected to the printer.';
    } on ApiException catch (e) {
      if (mounted) {
        final why = e.isNetwork ? 'No internet, so the receipt could not be sent. Press "Mark & Print Receipt" to try again.' : e.message;
        showMessage(context, why, error: true);
      }
      return null;
    }
  }

  Future<void> _undo(AttendanceItem item, String event) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove this check-in?'),
        content: Text('${item.name} will no longer be marked present today.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(100, 48), backgroundColor: context.colors.danger),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(attendanceRepoProvider).undo(item.id);
      ref.invalidate(todayProvider(event));
      if (mounted) showMessage(context, 'Removed ${item.name}');
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final event = ref.watch(selectedEventProvider);
    final pending = ref.watch(pendingCountProvider);

    return ValueListenableBuilder<DateTime?>(valueListenable: _dateN, builder: (context, day, _) => _page(context, text, event, pending, day));
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _dateN.value ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      helpText: 'Attendance of which day?',
    );
    if (d == null || !mounted) return;
    _reset();
    _dateN.value = _isoDate(d) == _isoDate(now) ? null : d; // today is the normal marking view
  }

  Widget _page(BuildContext context, TextTheme text, String? event, int pending, DateTime? day) {
    final history = day != null;
    return RefreshIndicator(
      onRefresh: () async {
        if (event != null) ref.invalidate(history ? dayProvider((event: event, date: _isoDate(day))) : todayProvider(event));
        await ref.read(pendingCountProvider.notifier).sync();
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(kPagePadding, 12, kPagePadding, 0),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (pending > 0) ...[
                  StatusBanner(
                    icon: Icons.cloud_upload_outlined,
                    text: '$pending check-in${pending == 1 ? '' : 's'} waiting to sync',
                    action: TextButton(
                      onPressed: () async {
                        final n = await ref.read(pendingCountProvider.notifier).sync();
                        if (context.mounted) {
                          showMessage(context, n > 0 ? 'Synced $n check-in${n == 1 ? '' : 's'}.' : 'Still offline. Will retry automatically.');
                        }
                      },
                      child: const Text('Sync now'),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    const Expanded(child: EventPicker()),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'Attendance history',
                      child: IconButton.filledTonal(onPressed: _pickDay, icon: const Icon(Icons.history_rounded)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (history) ...[
                  StatusBanner(
                    icon: Icons.lock_clock_outlined,
                    text: 'Viewing ${_isoDate(day)}. Attendance can only be marked for today.',
                    action: TextButton(onPressed: () => _dateN.value = null, child: const Text('Today')),
                  ),
                  const SizedBox(height: 10),
                ] else ...[
                  _SearchBox(controller: _search, searching: _searchingN, onChanged: _onChanged, onClear: _reset),
                  const SizedBox(height: 10),
                ],
                if (!history)
                  ValueListenableBuilder<List<Person>>(
                    valueListenable: _resultsN,
                    builder: (context, results, _) => ValueListenableBuilder<Person?>(
                      valueListenable: _personN,
                      builder: (context, person, _) => results.isEmpty || person != null
                          ? const SizedBox.shrink()
                          : Card(
                              child: Column(
                                children: [
                                  for (final p in results)
                                    ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                        child: Text(p.name.isEmpty ? '?' : p.name[0].toUpperCase(), style: text.titleSmall),
                                      ),
                                      title: Text(p.name, style: text.titleSmall),
                                      onTap: () {
                                        _search.text = p.mob;
                                        _lookup(p.mob);
                                      },
                                    ),
                                ],
                              ),
                            ),
                    ),
                  ),
                if (!history)
                  ListenableBuilder(
                    listenable: Listenable.merge([_personN, _newMobN, _offlineN, _editN, _busyN]),
                    builder: (context, _) {
                      final boot = ref.read(bootstrapProvider).value;
                      if (_personN.value != null) return _markCard(text, boot, _personN.value!, isNew: false);
                      if (_newMobN.value != null) return _markCard(text, boot, null, isNew: true);
                      return const SizedBox.shrink();
                    },
                  ),
                SectionTitle(
                  history ? 'Attendance on ${_isoDate(day)}' : "Today's attendance",
                  trailing: event == null ? null : _PresentCount(event: event, date: history ? _isoDate(day) : null),
                ),
              ]),
            ),
          ),
          if (event == null)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: Text('Choose an event')),
              ),
            )
          else if (history)
            _DaySliver(event: event, date: _isoDate(day))
          else
            _TodaySliver(event: event, onUndo: _undo),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  /// The fields shown for a registered person: all of them after the edit button, otherwise only the empty ones.
  Set<String> _shownFields(Person p) => _editN.value
      ? {
          'name',
          'gender',
          'level',
          'occupation',
          'college',
          'branch',
          'pg',
          'area',
          'guide',
          'dob',
          'stay',
          'skills',
          'interests',
          'chanting',
          'feedback',
          'comments',
        }
      : unfilledFields(p);

  Widget _markCard(TextTheme text, Bootstrap? boot, Person? p, {required bool isNew}) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: isNew ? _formKey : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isNew ? Icons.person_add_alt_1_outlined : Icons.verified_user_outlined,
                  color: isNew ? context.colors.warning : context.colors.success,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isNew ? 'Not registered: ${_newMob ?? ''}' : (_offlinePerson ? '${p!.mob}  (offline)' : '${p!.name}  •  ${p.mob}'),
                    style: text.titleSmall,
                  ),
                ),
                if (!isNew && !_offlinePerson)
                  IconButton(
                    tooltip: _editN.value ? 'Show only empty details' : 'Edit details',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(_editN.value ? Icons.close : Icons.edit_outlined, size: 20),
                    onPressed: () => _editN.value = !_editN.value,
                  ),
              ],
            ),
            if (!isNew && !_offlinePerson)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  [
                    if (p!.level.isNotEmpty) p.level,
                    'Attended ${p.attendanceCount} time${p.attendanceCount == 1 ? '' : 's'}',
                    if (p.lastAttendedOn.isNotEmpty) 'last on ${p.lastAttendedOn}',
                    if (p.guide.isNotEmpty) 'Guide: ${p.guide}',
                  ].join('  •  '),
                  style: text.bodyMedium,
                ),
              ),
            const SizedBox(height: 10),
            if (_offlinePerson)
              Text('Offline: will be sent later', style: text.bodyMedium)
            else if (isNew)
              PersonFields(form: _form, boot: boot)
            else if (_shownFields(p!).isNotEmpty) ...[
              if (!_editN.value)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text('Not filled yet (optional):', style: text.labelLarge),
                ),
              PersonFields(form: _form, boot: boot, requireLevel: false, only: _shownFields(p)),
            ],
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _busyN.value ? null : () => _mark(isNew: isNew),
              icon: _busyN.value
                  ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 3))
                  : const Icon(Icons.check_circle_outline),
              label: Text(isNew ? 'Register & Mark Attendance' : 'Mark Attendance'),
              style: FilledButton.styleFrom(backgroundColor: context.colors.success),
            ),
            if (!kIsWeb) ...[
              // thermal printers are reached over Bluetooth/USB, only in the Android app
              const SizedBox(height: kGapS),
              OutlinedButton.icon(
                onPressed: _busyN.value ? null : () => _mark(isNew: isNew, print: true),
                icon: const Icon(Icons.print_outlined),
                label: Text(isNew ? 'Register, Mark & Print Receipt' : 'Mark & Print Receipt'),
              ),
              const SizedBox(height: kGapS),
              const PrinterStatusChip(),
            ],
          ],
        ),
      ),
    ),
  );
}

/// The search field. Rebuilds only itself (clear button, spinner), never the page.
class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.controller, required this.searching, required this.onChanged, required this.onClear});
  final TextEditingController controller;
  final ValueNotifier<bool> searching;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    onChanged: onChanged,
    keyboardType: TextInputType.text,
    textInputAction: TextInputAction.search,
    autocorrect: false,
    enableSuggestions: false, // suggestions and autocorrect on the keyboard cause lag and swallowed keystrokes
    decoration: InputDecoration(
      labelText: 'Mobile number or name',
      prefixIcon: const Icon(Icons.search_rounded),
      suffixIcon: ListenableBuilder(
        listenable: Listenable.merge([controller, searching]),
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (searching.value)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
              ),
            if (controller.text.isNotEmpty) IconButton(tooltip: 'Clear', icon: const Icon(Icons.close_rounded), onPressed: onClear),
          ],
        ),
      ),
    ),
  );
}

class _PresentCount extends ConsumerWidget {
  const _PresentCount({required this.event, this.date});
  final String event;
  final String? date; // null = today
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = date == null
        ? ref.watch(todayProvider(event).select((v) => v.value?.length))
        : ref.watch(dayProvider((event: event, date: date!)).select((v) => v.value?.length));
    return n == null ? const SizedBox.shrink() : Chip(avatar: const Icon(Icons.groups_rounded, size: 20), label: Text('$n present'));
  }
}

/// Today's list, built lazily row by row so it stays smooth even with hundreds of people.
class _TodaySliver extends ConsumerWidget {
  const _TodaySliver({required this.event, required this.onUndo});
  final String event;
  final Future<void> Function(AttendanceItem, String) onUndo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final me = ref.watch(authProvider).value;
    final today = ref.watch(todayProvider(event));
    return today.when(
      loading: () => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => SliverToBoxAdapter(
        child: ErrorView(message: e is ApiException ? e.message : 'Could not load the list.', onRetry: () => ref.invalidate(todayProvider(event))),
      ),
      data: (items) => items.isEmpty
          ? SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Center(child: Text('No one marked yet today.', style: text.bodyLarge)),
              ),
            )
          : SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: kPagePadding),
              sliver: SliverList.separated(
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final it = items[i];
                  return RepaintBoundary(
                    child: Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: context.colors.success.withValues(alpha: 0.14),
                          child: Icon(Icons.check_rounded, color: context.colors.success),
                        ),
                        title: Text(it.name.isEmpty ? it.mob : it.name),
                        subtitle: Text('${it.mob}  •  ${shortTime(it.ts)}${it.markedBy.isEmpty ? '' : '  •  by ${it.markedBy}'}'),
                        trailing: (it.markedByMob == me?.mob || (me?.isStaff ?? false))
                            ? IconButton(
                                tooltip: 'Undo',
                                icon: Icon(Icons.undo_rounded, color: scheme.onSurfaceVariant),
                                onPressed: () => onUndo(it, event),
                              )
                            : null,
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

/// Calls [mob] straight away (no dialer screen) in the Android app; on the website it opens the device's dialer instead.
Future<void> dialNow(String mob) async {
  final number = '+91$mob';
  if (!kIsWeb && await FlutterPhoneDirectCaller.callNumber(number) == true) return;
  await launchUrl(Uri.parse('tel:$number'));
}

/// An earlier day's list (read only). Only the phone icon calls; tapping the row does nothing.
class _DaySliver extends ConsumerWidget {
  const _DaySliver({required this.event, required this.date});
  final String event, date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final key = (event: event, date: date);
    return ref
        .watch(dayProvider(key))
        .when(
          loading: () => const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (e, _) => SliverToBoxAdapter(
            child: ErrorView(message: e is ApiException ? e.message : 'Could not load the list.', onRetry: () => ref.invalidate(dayProvider(key))),
          ),
          data: (items) => items.isEmpty
              ? SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(child: Text('No attendance was marked on this day.', style: text.bodyLarge)),
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: kPagePadding),
                  sliver: SliverList.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final it = items[i];
                      return RepaintBoundary(
                        child: Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: context.colors.success.withValues(alpha: 0.14),
                              child: Icon(Icons.check_rounded, color: context.colors.success),
                            ),
                            title: Text(it.name.isEmpty ? it.mob : it.name),
                            subtitle: Text('${it.mob}  •  ${shortTime(it.ts)}${it.markedBy.isEmpty ? '' : '  •  by ${it.markedBy}'}'),
                            trailing: it.mob.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Call ${it.mob}',
                                    icon: Icon(Icons.call, color: context.colors.success),
                                    onPressed: () => dialNow(it.mob),
                                  ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
        );
  }
}
