import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/cache.dart';
import '../../core/config.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
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
    for (final n in [_resultsN, _personN, _newMobN, _busyN, _searchingN, _offlineN]) {
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
    _searchingN.value = false;
    _form.clear();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    final q = v.trim();
    if (_personN.value != null) _personN.value = null;
    if (_newMobN.value != null) _newMobN.value = null;
    if (_offlineN.value) _offlineN.value = false;
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

  Future<void> _mark({required bool isNew}) async {
    final event = ref.read(selectedEventProvider);
    final mob = _person?.mob ?? _newMob;
    if (event == null || mob == null) return;
    if (isNew && !_formKey.currentState!.validate()) return;
    _busyN.value = true;
    try {
      final f = _form.toJson();
      final r = await ref
          .read(attendanceRepoProvider)
          .mark(
            mob: mob,
            event: event,
            label: _person?.name ?? _form.name.text.trim(),
            edits: (isNew || _offlinePerson) ? null : f,
            register: isNew ? f : null,
            allowQueue: ref.read(bootstrapProvider).value?.offlineEnabled ?? false,
          );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      if (r.queued) {
        showMessage(context, '${r.name.isEmpty ? mob : r.name} saved offline. It will be sent automatically.');
        ref.read(pendingCountProvider.notifier).refresh();
      } else if (r.status == 'already') {
        showMessage(context, '${r.name} is already marked present today.');
      } else {
        showMessage(context, '${r.registered ? 'Registered and marked' : 'Marked present'}: ${r.name}');
      }
      ref.invalidate(todayProvider(event));
      _reset();
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) _busyN.value = false;
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

    return RefreshIndicator(
      onRefresh: () async {
        if (event != null) ref.invalidate(todayProvider(event));
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
                  const SizedBox(height: 12),
                ],
                const EventPicker(),
                const SizedBox(height: 14),
                _SearchBox(controller: _search, searching: _searchingN, onChanged: _onChanged, onClear: _reset),
                const SizedBox(height: 10),
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
                ListenableBuilder(
                  listenable: Listenable.merge([_personN, _newMobN, _offlineN, _busyN]),
                  builder: (context, _) {
                    final boot = ref.read(bootstrapProvider).value;
                    if (_personN.value != null) return _markCard(text, boot, _personN.value!, isNew: false);
                    if (_newMobN.value != null) return _markCard(text, boot, null, isNew: true);
                    return const SizedBox.shrink();
                  },
                ),
                SectionTitle("Today's attendance", trailing: event == null ? null : _PresentCount(event: event)),
              ]),
            ),
          ),
          if (event == null)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('Choose an event')),
              ),
            )
          else
            _TodaySliver(event: event, onUndo: _undo),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

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
              ],
            ),
            if (!isNew && !_offlinePerson)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Attended ${p!.attendanceCount} time${p.attendanceCount == 1 ? '' : 's'}${p.lastAttendedOn.isEmpty ? '' : '  •  last on ${p.lastAttendedOn}'}',
                  style: text.bodyMedium,
                ),
              ),
            if (isNew)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Fill the details to register and mark present in one step.', style: text.bodyMedium),
              ),
            const SizedBox(height: 14),
            if (_offlinePerson)
              Text('Offline: this check-in will be saved on your phone and sent automatically.', style: text.bodyMedium)
            else if (isNew)
              PersonFields(form: _form, boot: boot)
            else
              PersonFields(form: _form, boot: boot),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busyN.value ? null : () => _mark(isNew: isNew),
              icon: _busyN.value
                  ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 3))
                  : const Icon(Icons.check_circle_outline),
              label: Text(isNew ? 'Register & mark present' : 'Mark present'),
              style: FilledButton.styleFrom(backgroundColor: context.colors.success),
            ),
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
      hintText: 'Type 3+ digits or letters',
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
  const _PresentCount({required this.event});
  final String event;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(todayProvider(event).select((v) => v.value?.length));
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
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => SliverToBoxAdapter(
        child: ErrorView(message: e is ApiException ? e.message : 'Could not load the list.', onRetry: () => ref.invalidate(todayProvider(event))),
      ),
      data: (items) => items.isEmpty
          ? SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
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
