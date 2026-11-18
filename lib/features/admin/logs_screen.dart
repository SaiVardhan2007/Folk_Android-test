import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout.dart';
import '../../core/util.dart';
import 'admin_repo.dart';
import 'paged_list_screen.dart';

/// Admin → Settings → Activity log: every change made by any user, coordinator or admin, newest first.
class LogsScreen extends ConsumerWidget {
  const LogsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(adminRepoProvider);
    return PagedListScreen(
      title: 'Activity log',
      searchLabel: 'Search person, action or detail',
      emptyText: 'No activity recorded yet.',
      chips: const {
        'role': ['Admin', 'Coordinator', 'Public'],
      },
      load: repo.logs,
      export: (f) => repo.shareCsv('/admin/export/logs', 'folk-activity-log.csv', query: f),
      itemBuilder: (context, row) {
        final text = Theme.of(context).textTheme;
        final at = '${row['at'] ?? ''}';
        final who = '${row['user_name'] ?? ''}'.isEmpty ? 'Unknown' : '${row['user_name']}';
        final about = [row['target'], row['details']].where((e) => (e ?? '').toString().isNotEmpty).join('  ·  ');
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(kGapM),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${row['action'] ?? ''}', style: text.titleSmall),
                Text('$who  ·  ${row['role'] ?? ''}', style: text.bodyMedium),
                if (about.isNotEmpty) Text(about, style: text.bodyMedium),
                const SizedBox(height: kGapXS),
                Text(at.length >= 10 ? '${at.substring(0, 10)}  ${shortTime(at)}' : at, style: text.labelSmall),
              ],
            ),
          ),
        );
      },
    );
  }
}
