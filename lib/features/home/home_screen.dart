import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/cache.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../core/widgets.dart';
import '../admin/admin_repo.dart';
import '../admin/link_card.dart';
import '../auth/auth_controller.dart';
import '../calls/calling_status_screen.dart';
import '../../core/layout.dart';

final homeStatsProvider = StreamProvider.autoDispose.family<int, String>((ref, event) {
  return cachedGet(ref, '/home', (r) => (r['registered'] as num?)?.toInt() ?? 0, query: {'event': event});
});

/// A coordinator's calls for one event and which of the people they called came.
typedef CallSummary = ({int called, int came, List<Map<String, dynamic>> calls});
final myCallSummaryProvider = StreamProvider.autoDispose.family<CallSummary, String>((ref, event) {
  return cachedGet(
    ref,
    '/my/calls/summary',
    (r) => (
      called: (r['called'] as num?)?.toInt() ?? 0,
      came: (r['came'] as num?)?.toInt() ?? 0,
      calls: ((r['calls'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
    ),
    query: {'event': event},
  );
});

/// Registration links assigned to the signed-in staff member (empty for most people).
final myLinksProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) => ref.read(adminRepoProvider).myLinks());

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Standard refresh: the numbers load when the screen opens, when the app returns to the foreground, and on pull-down. No timer.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final e = ref.read(selectedEventProvider);
    if (state == AppLifecycleState.resumed && e != null) {
      ref.invalidate(homeStatsProvider(e));
      ref.invalidate(callProgressProvider(e));
      if (ref.read(authProvider).value?.isCoordinator ?? false) ref.invalidate(myCallSummaryProvider(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final me = ref.watch(authProvider).value;
    final boot = ref.watch(bootstrapProvider);
    final event = ref.watch(selectedEventProvider);
    final progress = event == null ? null : ref.watch(callProgressProvider(event));
    final eventName = boot.value?.events.where((e) => e.code == event).firstOrNull?.name ?? event ?? '';
    void openStatus() => Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => CallingStatusScreen(event: event!, eventName: eventName),
      ),
    );
    final isCoordinator = me?.isCoordinator ?? false;
    final callSummary = (event == null || !isCoordinator) ? null : ref.watch(myCallSummaryProvider(event));
    final myLinks = (me?.isStaff ?? false) ? (ref.watch(myLinksProvider).value ?? const <Map<String, dynamic>>[]) : const <Map<String, dynamic>>[];

    return PageBody(
      onRefresh: () async {
        ref.invalidate(bootstrapProvider);
        ref.invalidate(myLinksProvider);
        if (event != null) {
          ref.invalidate(callProgressProvider(event));
          if (isCoordinator) ref.invalidate(myCallSummaryProvider(event));
        }
      },
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), gradient: kBrandGradient),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hare Krishna', style: text.bodyLarge?.copyWith(color: kOnBrand.withValues(alpha: 0.85))),
              const SizedBox(height: 2),
              Text(firstName(me?.name ?? ''), style: text.headlineMedium?.copyWith(color: kOnBrand)),
              const SizedBox(height: 10),
              if (me != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: kOnBrand.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
                  child: Text(me.tag, style: text.labelMedium?.copyWith(color: kOnBrand)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        boot.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => ErrorView(message: e is ApiException ? e.message : 'Could not load.', onRetry: () => ref.invalidate(bootstrapProvider)),
          data: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const EventPicker(),
              const SizedBox(height: 10),
              StatGrid(
                children: [
                  StatTile(
                    icon: Icons.assignment_ind_outlined,
                    label: 'Assigned contacts',
                    value: progress?.value?.assigned,
                    color: context.colors.brand,
                    onTap: event == null ? null : openStatus,
                  ),
                  StatTile(
                    icon: Icons.phone_in_talk_rounded,
                    label: 'Called',
                    value: progress?.value?.done,
                    color: context.colors.success,
                    onTap: event == null ? null : openStatus,
                  ),
                  if (isCoordinator)
                    StatTile(
                      icon: Icons.directions_walk_rounded,
                      label: 'Attended',
                      value: callSummary?.value?.came,
                      color: context.colors.accent,
                      onTap: callSummary?.value == null ? null : () => _showCalls(context, callSummary!.value!, cameOnly: true),
                    ),
                ],
              ),
              const SizedBox(height: kGapM),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: event == null ? null : openStatus,
                  icon: const Icon(Icons.leaderboard_rounded),
                  label: const Text('Coordinators and their contacts'),
                ),
              ),
            ],
          ),
        ),
        if (myLinks.isNotEmpty) ...[
          const SectionTitle('Your registration links'),
          for (final l in myLinks)
            Padding(
              padding: const EdgeInsets.only(bottom: kGapS),
              child: LinkCard(link: l),
            ),
        ],
      ],
    );
  }
}

void _showCalls(BuildContext context, CallSummary data, {required bool cameOnly}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _CallsSheet(data: data, cameOnly: cameOnly),
);

/// Who the coordinator called for this event, and who of them came.
class _CallsSheet extends StatelessWidget {
  const _CallsSheet({required this.data, required this.cameOnly});
  final CallSummary data;
  final bool cameOnly;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final rows = cameOnly ? data.calls.where((r) => r['came'] == true).toList() : data.calls;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(kPagePadding, 0, kPagePadding, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(cameOnly ? 'Came (${rows.length})' : 'Calls made (${rows.length})', style: text.titleLarge),
              const SizedBox(height: 8),
              if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: Text(
                      cameOnly ? 'None of the people you called have come yet.' : 'You have not made any calls for this event yet.',
                      style: text.bodyLarge,
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final r in rows)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            r['came'] == true ? Icons.check_circle : Icons.phone_in_talk_outlined,
                            color: r['came'] == true ? context.colors.success : null,
                          ),
                          title: Text('${r['name'] ?? ''}'.isEmpty ? '${r['mob']}' : '${r['name']}'),
                          subtitle: Text(
                            [
                              '${r['mob']}',
                              if (!cameOnly) '${r['status']}${'${r['called_at']}'.isEmpty ? '' : ' • ${shortTime('${r['called_at']}')}'}',
                              if (cameOnly && '${r['came_at']}'.isNotEmpty) 'Came ${shortTime('${r['came_at']}')}',
                            ].join('\n'),
                          ),
                          isThreeLine: true,
                          trailing: !cameOnly && r['came'] == true
                              ? Text('Came', style: text.labelLarge?.copyWith(color: context.colors.success))
                              : null,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
