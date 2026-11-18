import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/cache.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';

final _analyticsProvider = StreamProvider.autoDispose.family<Map<String, dynamic>, String>((ref, key) {
  return cachedGet(ref, '/admin/analytics', (j) => j, query: Uri.splitQueryString(key));
});

class AnalyticsTab extends ConsumerStatefulWidget {
  const AnalyticsTab({super.key});
  @override
  ConsumerState<AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends ConsumerState<AnalyticsTab> with AutomaticKeepAliveClientMixin {
  String _range = 'all', _event = '', _level = '', _gender = '';

  @override
  bool get wantKeepAlive => true;

  String get _key {
    final today = istNow();
    final from = switch (_range) {
      'today' => istDate(today),
      '7' => istDate(today.subtract(const Duration(days: 6))),
      '30' => istDate(today.subtract(const Duration(days: 29))),
      _ => '',
    };
    return Uri(queryParameters: {'from': from, 'to': from.isEmpty ? '' : istDate(today), 'event': _event, 'level': _level, 'gender': _gender}).query;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final boot = ref.watch(bootstrapProvider).value;
    final key = _key;
    final data = ref.watch(_analyticsProvider(key));
    final text = Theme.of(context).textTheme;

    return PageBody(
      onRefresh: () async => ref.refresh(_analyticsProvider(key).future),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final r in const {'today': 'Today', '7': '7 days', '30': '30 days', 'all': 'All time'}.entries)
              ChoiceChip(label: Text(r.value), selected: _range == r.key, onSelected: (_) => setState(() => _range = r.key)),
          ],
        ),
        const SizedBox(height: 12),
        FieldGrid(
          children: [
            OptionDropdown(
              label: 'Event',
              value: _event,
              options: [for (final e in boot?.events ?? <FolkEvent>[]) e.code],
              labelOf: (c) => boot!.events.firstWhere((e) => e.code == c).name,
              onChanged: (v) => setState(() => _event = v),
            ),
            OptionDropdown(label: 'Level', value: _level, options: boot?.levels ?? const [], onChanged: (v) => setState(() => _level = v)),
            OptionDropdown(
              label: 'Gender',
              value: _gender,
              options: const ['M', 'F'],
              labelOf: genderLabel,
              onChanged: (v) => setState(() => _gender = v),
            ),
          ],
        ),
        const SizedBox(height: 8),
        data.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) =>
              ErrorView(message: e is ApiException ? e.message : 'Could not load analytics.', onRetry: () => ref.invalidate(_analyticsProvider(key))),
          data: (d) {
            final k = Map<String, dynamic>.from(d['kpi'] as Map);
            List<Map<String, dynamic>> rows(String name) => ((d[name] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
            List<_Bar> counts(String name) =>
                rows(name).map((r) => _Bar(r['label'] as String, (r['value'] as num).toInt(), hint: r['hint'] as String?)).toList();
            List<_Bar> groups(String name) => rows(name)
                .map((r) => _Bar(r['key'] as String, (r['checkins'] as num).toInt(), hint: '${r['people']} people • ${r['attended']} attended'))
                .toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                StatGrid(
                  children: [
                    StatTile(label: 'People', value: k['people'], color: context.colors.brand, icon: Icons.people_alt_rounded),
                    StatTile(
                      label: 'Attended',
                      value: '${k['attended']}  (${k['rate']}%)',
                      color: context.colors.success,
                      icon: Icons.how_to_reg_rounded,
                    ),
                    StatTile(label: 'Check-ins', value: k['checkins'], color: context.colors.accent, icon: Icons.checklist_rtl_rounded),
                    StatTile(label: 'Not attended', value: k['notAttended'], color: context.colors.warning, icon: Icons.person_off_rounded),
                  ],
                ),
                _BarCard('By level', groups('byLevel'), unit: 'check-ins'),
                _BarCard('By gender', groups('byGender'), unit: 'check-ins'),
                _BarCard('By role', groups('byTag'), unit: 'check-ins'),
                _BarCard('By weekday', counts('weekday'), unit: 'check-ins'),
                _BarCard('How often people come', counts('frequency'), unit: 'people'),
                _BarCard('Top attendees', counts('topAttendees'), unit: 'times'),
                _BarCard('Marked by volunteer', counts('byVolunteer'), unit: 'check-ins'),
                _BarCard('Top residences / PG', counts('topPg'), unit: 'people'),
                _BarCard('Top companies / colleges', counts('topProfession'), unit: 'people'),
                _BarCard('Registered by', counts('byRegistrar'), unit: 'people'),
                const SizedBox(height: 8),
                Text('Updated just now. Pull down to refresh.', style: text.bodySmall),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Bar {
  const _Bar(this.label, this.value, {this.hint});
  final String label;
  final int value;
  final String? hint;
}

class _BarCard extends StatelessWidget {
  const _BarCard(this.title, this.bars, {required this.unit});
  final String title, unit;
  final List<_Bar> bars;

  @override
  Widget build(BuildContext context) {
    if (bars.isEmpty || bars.every((b) => b.value == 0 && b.hint == null)) return const SizedBox.shrink();
    final max = bars.map((b) => b.value).fold<int>(1, (a, b) => b > a ? b : a);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: text.titleSmall),
              const SizedBox(height: 10),
              for (final b in bars)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(b.label, style: text.bodyLarge, overflow: TextOverflow.ellipsis),
                          ),
                          Text('${b.value}', style: text.titleSmall),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: b.value / max,
                          minHeight: 10,
                          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                        ),
                      ),
                      if (b.hint != null && b.hint!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(b.hint!, style: text.bodySmall),
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
