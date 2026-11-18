import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'admin_repo.dart';
import 'paged_list_screen.dart';

/// Admin → Events → Registrations: everyone registered for one event, with the answers they gave.
class RegistrationsScreen extends ConsumerWidget {
  const RegistrationsScreen({super.key, required this.eventCode, required this.eventName});
  final String eventCode, eventName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(adminRepoProvider);
    return PagedListScreen(
      title: '$eventName registrations',
      searchLabel: 'Search name or mobile',
      emptyText: 'No registrations for this event.',
      fixedFilters: {'event': eventCode},
      chips: const {
        'kind': ['Volunteers', 'Dinner', 'Donors', 'Transport'],
      },
      load: repo.registrations,
      export: (f) => repo.shareCsv('/admin/export/registrations', 'folk-registrations-$eventCode.csv', query: f),
      header: (context, r) {
        final s = Map<String, dynamic>.from(r['summary'] as Map? ?? const {});
        return StatStrip(
          children: [
            MiniStat(label: 'Registered', value: s['total'], color: context.colors.brand),
            MiniStat(label: 'Volunteers', value: s['volunteers'], color: context.colors.success),
            MiniStat(label: 'Dinner', value: s['dinner'], color: context.colors.accent),
            MiniStat(label: 'Donors', value: s['donors'], color: context.colors.warning),
            MiniStat(label: 'Transport', value: s['transport'], color: context.colors.danger),
          ],
        );
      },
      itemBuilder: (context, row) {
        final text = Theme.of(context).textTheme;
        final tags = <String>[
          if (row['volunteer'] == 1) 'Volunteer${(row['volunteer_slot'] ?? '').toString().isEmpty ? '' : ' · ${row['volunteer_slot']}'}',
          if ((row['service'] ?? '').toString().isNotEmpty) '${row['service']}',
          if (row['dinner'] == 1) 'Dinner',
          if (row['donation'] == 'Opted to Donate') 'Will donate',
          if (row['transport_required'] == 1) 'Needs transport',
          if ((row['standard'] ?? '').toString().isNotEmpty) '${row['standard']}',
        ];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(kGapM),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${row['person_name'] ?? ''}', style: text.titleSmall),
                Text([row['person_mob'], row['registration_no']].where((e) => (e ?? '').toString().isNotEmpty).join('  ·  '), style: text.bodyMedium),
                if (tags.isNotEmpty) ...[
                  const SizedBox(height: kGapS),
                  Wrap(
                    spacing: kGapS,
                    runSpacing: kGapXS,
                    children: [for (final t in tags) Chip(label: Text(t), visualDensity: VisualDensity.compact)],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
