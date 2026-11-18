import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'admin_repo.dart';
import 'feedback_screen.dart';
import 'registrations_screen.dart';

final _eventSummaryProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, code) => ref.read(adminRepoProvider).eventSummary(code),
);

/// Admin → Events → tap an event: registered, attended, feedback and call totals for that one event.
class EventDetailScreen extends ConsumerWidget {
  const EventDetailScreen({super.key, required this.eventCode, required this.eventName, this.isCurrent = false});
  final String eventCode, eventName;
  final bool isCurrent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final summary = ref.watch(_eventSummaryProvider(eventCode));
    int n(Map<String, dynamic> s, String k) => (s[k] as num?)?.toInt() ?? 0;

    Widget section(String title) => Padding(
      padding: const EdgeInsets.only(top: kGapM, bottom: kGapS),
      child: Text(title, style: text.titleSmall),
    );

    return Scaffold(
      appBar: AppBar(title: Text(eventName)),
      body: summary.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          message: e is ApiException ? e.message : 'Could not load this event.',
          onRetry: () => ref.invalidate(_eventSummaryProvider(eventCode)),
        ),
        data: (s) {
          final registered = n(s, 'registered');
          final attended = n(s, 'attended');
          final days = [for (final d in (s['days'] as List? ?? const [])) Map<String, dynamic>.from(d as Map)];
          final avg = (s['average'] as num?) ?? 0;
          return PageBody(
            onRefresh: () async {
              ref.invalidate(_eventSummaryProvider(eventCode));
              await ref.read(_eventSummaryProvider(eventCode).future);
            },
            children: [
              Text('Code: $eventCode${isCurrent ? '  ·  Current event' : ''}', style: text.bodyMedium),
              section('Registration'),
              StatGrid(
                children: [
                  StatTile(
                    label: 'Registered',
                    value: registered,
                    color: context.colors.brand,
                    onTap: () => Navigator.of(context, rootNavigator: true).push(
                      MaterialPageRoute<void>(builder: (_) => RegistrationsScreen(eventCode: eventCode, eventName: eventName)),
                    ),
                  ),
                  StatTile(label: 'Volunteers', value: n(s, 'volunteers'), color: context.colors.brand),
                  StatTile(label: 'Dinner', value: n(s, 'dinner'), color: context.colors.brand),
                  StatTile(label: 'Donors', value: n(s, 'donors'), color: context.colors.brand),
                  StatTile(label: 'Need transport', value: n(s, 'transport'), color: context.colors.brand),
                ],
              ),
              section('Attendance'),
              StatGrid(
                children: [
                  StatTile(label: 'People attended', value: attended, color: context.colors.success),
                  StatTile(
                    label: 'Attended of registered',
                    value: registered == 0 ? '–' : '${(attended * 100 / registered).round()}%',
                    color: context.colors.success,
                  ),
                  StatTile(label: 'Check-ins', value: n(s, 'checkins'), color: context.colors.success),
                  StatTile(label: 'Days held', value: days.length, color: context.colors.success),
                ],
              ),
              if (days.isNotEmpty) ...[
                const SizedBox(height: kGapS),
                Card(
                  child: Column(
                    children: [
                      for (final d in days)
                        ListTile(
                          title: Text('${d['date']}'),
                          trailing: Text('${d['count']} marked', style: text.titleSmall),
                        ),
                    ],
                  ),
                ),
              ],
              section('Feedback'),
              StatGrid(
                children: [
                  StatTile(
                    label: 'Responses',
                    value: n(s, 'feedback'),
                    color: context.colors.brand,
                    onTap: () => Navigator.of(context, rootNavigator: true).push(
                      MaterialPageRoute<void>(builder: (_) => FeedbackScreen(eventCode: eventCode, eventName: eventName)),
                    ),
                  ),
                  StatTile(label: 'Average (of 5)', value: avg == 0 ? '–' : avg.toStringAsFixed(1), color: context.colors.success),
                ],
              ),
              section('Calls'),
              StatGrid(
                children: [
                  StatTile(label: 'Assigned', value: n(s, 'assigned'), color: context.colors.brand),
                  StatTile(label: 'Calls made', value: n(s, 'calls'), color: context.colors.brand),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
