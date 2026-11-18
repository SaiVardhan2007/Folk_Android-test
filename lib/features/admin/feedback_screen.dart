import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'admin_repo.dart';
import 'paged_list_screen.dart';

/// Admin → Events → Feedback: the answers people sent through the event's feedback form.
class FeedbackScreen extends ConsumerWidget {
  const FeedbackScreen({super.key, required this.eventCode, required this.eventName});
  final String eventCode, eventName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(adminRepoProvider);
    return PagedListScreen(
      title: '$eventName feedback',
      searchLabel: 'Search name or mobile',
      emptyText: 'No feedback yet. Share the Feedback form of this event.',
      fixedFilters: {'event': eventCode},
      load: repo.feedback,
      export: (f) => repo.shareCsv('/admin/export/feedback', 'folk-feedback-$eventCode.csv', query: f),
      header: (context, r) {
        final s = Map<String, dynamic>.from(r['summary'] as Map? ?? const {});
        final avg = (s['average'] as num?) ?? 0;
        return StatStrip(
          children: [
            MiniStat(label: 'Responses', value: s['total'], color: context.colors.brand),
            MiniStat(label: 'Average (of 5)', value: avg == 0 ? '-' : avg.toStringAsFixed(1), color: context.colors.success),
          ],
        );
      },
      itemBuilder: (context, row) {
        final text = Theme.of(context).textTheme;
        final rating = (row['rating'] as num?)?.toInt() ?? 0;
        Widget? answer(String label, Object? v) => '${v ?? ''}'.trim().isEmpty
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: kGapS),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: '$label  ', style: text.labelLarge),
                      TextSpan(text: '$v'.trim()),
                    ],
                  ),
                  style: text.bodyMedium,
                ),
              );
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(kGapM),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('${row['person_name'] ?? ''}', style: text.titleSmall)),
                    Icon(Icons.star_rounded, color: context.colors.warning),
                    Text('$rating / 5', style: text.titleSmall),
                  ],
                ),
                Text('${row['person_mob'] ?? ''}', style: text.bodyMedium),
                ?answer('Liked', row['liked']),
                ?answer('Can be better', row['improve']),
                ?answer('Comments', row['comments']),
              ],
            ),
          ),
        );
      },
    );
  }
}
