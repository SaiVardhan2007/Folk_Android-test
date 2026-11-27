import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/cache.dart';
import '../../core/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// One coordinator's calling progress for an event.
typedef CallerProgress = ({String name, int assigned, int done, int pending, int percent, bool complete});
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
          name: '${m['name'] ?? ''}',
          assigned: _n(m['assigned']),
          done: _n(m['done']),
          pending: _n(m['pending']),
          percent: _n(m['percent']),
          complete: m['complete'] == true,
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
                    padding: const EdgeInsets.all(24),
                    child: Center(child: Text(p.coordinators.isEmpty ? 'No contacts are assigned yet.' : 'Nobody here.', style: text.bodyLarge)),
                  )
                else
                  for (final c in rows) _CallerRow(c),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CallerRow extends StatelessWidget {
  const _CallerRow(this.c);
  final CallerProgress c;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final color = c.complete ? context.colors.success : context.colors.warning;
    return Card(
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
          ],
        ),
      ),
    );
  }
}
