import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/cache.dart';
import '../../core/layout.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../core/widgets.dart';

/// One coordinator's calling progress for an event.
typedef CallerProgress = ({
  String id,
  String name,
  int assigned,
  int done,
  int pending,
  int percent,
  bool complete,
  String lastCall,
  String waitingSince,
});
typedef CallProgress = ({int assigned, int done, int pending, int percent, List<CallerProgress> coordinators});

int _n(Object? v) => (v as num?)?.toInt() ?? 0;

/// Calling progress for an event: overall numbers and every coordinator (highest percentage first, as the server sorts them).
final callProgressProvider = StreamProvider.autoDispose.family<CallProgress, String>((ref, event) {
  return cachedGet(ref, '/calls/progress', (r) {
    final t = Map<String, dynamic>.from(r['totals'] as Map? ?? const {});
    return (
      assigned: _n(t['assigned']),
      done: _n(t['done']),
      pending: _n(t['pending']),
      percent: _n(t['percent']),
      coordinators: ((r['coordinators'] as List?) ?? const []).map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return (
          id: '${m['id'] ?? ''}',
          name: '${m['name'] ?? ''}',
          assigned: _n(m['assigned']),
          done: _n(m['done']),
          pending: _n(m['pending']),
          percent: _n(m['percent']),
          complete: m['complete'] == true,
          lastCall: '${m['last_call'] ?? ''}',
          waitingSince: '${m['waiting_since'] ?? ''}',
        );
      }).toList(),
    );
  }, query: {'event': event});
});

enum _Show { all, pending, completed }

/// Who has finished their calls and who is still pending, with the percentage done, highest first.
class CallingStatusScreen extends ConsumerStatefulWidget {
  const CallingStatusScreen({super.key, required this.event, required this.eventName});
  final String event, eventName;
  @override
  ConsumerState<CallingStatusScreen> createState() => _CallingStatusScreenState();
}

class _CallingStatusScreenState extends ConsumerState<CallingStatusScreen> {
  _Show _show = _Show.all;

  void _open(CallerProgress c) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CoordinatorContactsScreen(event: widget.event, id: c.id, name: c.name),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final data = ref.watch(callProgressProvider(widget.event));
    return Scaffold(
      appBar: AppBar(title: const Text('Calling status')),
      body: SafeArea(
        child: data.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorView(
            message: e is ApiException ? e.message : 'Could not load.',
            onRetry: () => ref.invalidate(callProgressProvider(widget.event)),
          ),
          data: (p) {
            final rows = p.coordinators
                .where(
                  (c) => switch (_show) {
                    _Show.all => true,
                    _Show.pending => !c.complete,
                    _Show.completed => c.complete,
                  },
                )
                .toList();
            return PageBody(
              onRefresh: () async => ref.invalidate(callProgressProvider(widget.event)),
              children: [
                Text(widget.eventName, style: text.titleMedium),
                const SizedBox(height: kGapM),
                StatGrid(
                  children: [
                    StatTile(label: 'Assigned', value: p.assigned, color: context.colors.brand),
                    StatTile(label: 'Called', value: p.done, color: context.colors.success),
                    StatTile(label: 'Pending', value: p.pending, color: context.colors.warning),
                    StatTile(label: 'Done', value: '${p.percent}%', color: context.colors.success),
                  ],
                ),
                const SizedBox(height: kGapM),
                SegmentedButton<_Show>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: _Show.all, label: Text('All')),
                    ButtonSegment(value: _Show.pending, label: Text('Pending')),
                    ButtonSegment(value: _Show.completed, label: Text('Completed')),
                  ],
                  selected: {_show},
                  onSelectionChanged: (s) => setState(() => _show = s.first),
                ),
                const SizedBox(height: kGapS),
                if (rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(child: Text(p.coordinators.isEmpty ? 'No contacts are assigned yet.' : 'Nobody here.', style: text.bodyLarge)),
                  )
                else
                  for (final c in rows) _CallerRow(c, onTap: () => _open(c)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CallerRow extends StatelessWidget {
  const _CallerRow(this.c, {required this.onTap});
  final CallerProgress c;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final color = c.complete ? context.colors.success : context.colors.warning;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(kGapL),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(c.name, style: text.titleSmall)),
                  Text('${c.percent}%', style: text.titleMedium?.copyWith(color: color)),
                ],
              ),
              const SizedBox(height: kGapS),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(value: c.percent / 100, minHeight: 8, color: color),
              ),
              const SizedBox(height: kGapS),
              Row(
                children: [
                  Expanded(child: Text('${c.done} of ${c.assigned} called', style: text.bodyMedium)),
                  Text(c.complete ? 'Completed' : '${c.pending} pending', style: text.labelLarge?.copyWith(color: color)),
                ],
              ),
              const SizedBox(height: kGapS),
              Text(
                c.lastCall.isEmpty ? 'No calls made yet' : 'Last call ${whenText(c.lastCall)}',
                style: text.bodyMedium?.copyWith(color: c.lastCall.isEmpty && c.pending > 0 ? context.colors.warning : null),
              ),
              if (c.waitingSince.isNotEmpty)
                Text(
                  'Oldest waiting: ${waitingText(c.waitingSince)}',
                  style: text.bodyMedium?.copyWith(color: daysSince(c.waitingSince) >= 2 ? context.colors.warning : null),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Whole days between a server time "YYYY-MM-DD HH:MM:SS" (India time) and today.
int daysSince(String ts) {
  final d = DateTime.tryParse(ts.length >= 10 ? ts.substring(0, 10) : '');
  if (d == null) return 0;
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day).difference(d).inDays;
}

/// "today 5:10 PM", "yesterday 9:00 AM", "3 days ago".
String whenText(String ts) {
  final n = daysSince(ts);
  if (n <= 0) return 'today ${shortTime(ts)}';
  if (n == 1) return 'yesterday ${shortTime(ts)}';
  return '$n days ago';
}

String waitingText(String ts) {
  final n = daysSince(ts);
  return n <= 0 ? 'since today' : (n == 1 ? '1 day' : '$n days');
}

typedef _Contact = ({String name, String status, bool pending, bool followUp, String assignedAt, String calledAt});
typedef _Contacts = ({String name, List<_Contact> contacts});

final _coordinatorContactsProvider = StreamProvider.autoDispose.family<_Contacts, ({String event, String id})>((ref, k) {
  return cachedGet(ref, '/calls/coordinator', (r) {
    return (
      name: '${r['name'] ?? ''}',
      contacts: ((r['contacts'] as List?) ?? const []).map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return (
          name: '${m['name'] ?? ''}',
          status: '${m['status'] ?? ''}',
          pending: m['pending'] == true,
          followUp: m['follow_up'] == true,
          assignedAt: '${m['assigned_at'] ?? ''}',
          calledAt: '${m['called_at'] ?? ''}',
        );
      }).toList(),
    );
  }, query: {'event': k.event, 'id': k.id});
});

/// The contacts handed to one coordinator: who is still waiting (longest waiting first, so anything left behind shows at the top) and who was called.
class CoordinatorContactsScreen extends ConsumerStatefulWidget {
  const CoordinatorContactsScreen({super.key, required this.event, required this.id, required this.name});
  final String event, id, name;
  @override
  ConsumerState<CoordinatorContactsScreen> createState() => _CoordinatorContactsState();
}

class _CoordinatorContactsState extends ConsumerState<CoordinatorContactsScreen> {
  _Show _show = _Show.all;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final key = (event: widget.event, id: widget.id);
    final data = ref.watch(_coordinatorContactsProvider(key));
    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      body: SafeArea(
        child: data.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) =>
              ErrorView(message: e is ApiException ? e.message : 'Could not load.', onRetry: () => ref.invalidate(_coordinatorContactsProvider(key))),
          data: (d) {
            final pending = d.contacts.where((c) => c.pending).toList();
            final called = d.contacts.where((c) => !c.pending).toList()..sort((a, b) => b.calledAt.compareTo(a.calledAt));
            final rows = switch (_show) {
              _Show.all => [...pending, ...called],
              _Show.pending => pending,
              _Show.completed => called,
            };
            return PageBody(
              onRefresh: () async => ref.invalidate(_coordinatorContactsProvider(key)),
              children: [
                StatGrid(
                  children: [
                    StatTile(label: 'Assigned', value: d.contacts.length, color: context.colors.brand),
                    StatTile(label: 'Called', value: called.length, color: context.colors.success),
                    StatTile(label: 'Pending', value: pending.length, color: context.colors.warning),
                  ],
                ),
                const SizedBox(height: kGapM),
                SegmentedButton<_Show>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: _Show.all, label: Text('All')),
                    ButtonSegment(value: _Show.pending, label: Text('Pending')),
                    ButtonSegment(value: _Show.completed, label: Text('Called')),
                  ],
                  selected: {_show},
                  onSelectionChanged: (s) => setState(() => _show = s.first),
                ),
                const SizedBox(height: kGapS),
                if (rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(child: Text('Nobody here.', style: text.bodyLarge)),
                  )
                else
                  for (final c in rows)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        c.pending ? Icons.hourglass_bottom_rounded : Icons.check_circle,
                        color: c.pending ? (daysSince(c.assignedAt) >= 2 ? context.colors.warning : null) : context.colors.success,
                      ),
                      title: Text(c.name.isEmpty ? 'Unnamed' : c.name),
                      subtitle: Text(
                        c.pending
                            ? 'Waiting ${waitingText(c.assignedAt)}${c.followUp ? ' • follow-up' : ''}'
                            : '${c.status} • ${whenText(c.calledAt)}',
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}
