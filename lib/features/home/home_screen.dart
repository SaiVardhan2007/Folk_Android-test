import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/cache.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../core/widgets.dart';
import '../admin/admin_repo.dart';
import '../admin/link_card.dart';
import '../auth/auth_controller.dart';
import '../../core/layout.dart';

final homeStatsProvider = StreamProvider.autoDispose.family<({int registered, int marked}), String>((ref, event) {
  return cachedGet(
    ref,
    '/home',
    (r) => (registered: (r['registered'] as num?)?.toInt() ?? 0, marked: (r['marked_today'] as num?)?.toInt() ?? 0),
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
    if (state == AppLifecycleState.resumed && e != null) ref.invalidate(homeStatsProvider(e));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final me = ref.watch(authProvider).value;
    final boot = ref.watch(bootstrapProvider);
    final event = ref.watch(selectedEventProvider);
    final stats = event == null ? null : ref.watch(homeStatsProvider(event));
    final myLinks = (me?.isStaff ?? false) ? (ref.watch(myLinksProvider).value ?? const <Map<String, dynamic>>[]) : const <Map<String, dynamic>>[];

    return PageBody(
      onRefresh: () async {
        ref.invalidate(bootstrapProvider);
        ref.invalidate(myLinksProvider);
        if (event != null) ref.invalidate(homeStatsProvider(event));
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
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => ErrorView(message: e is ApiException ? e.message : 'Could not load.', onRetry: () => ref.invalidate(bootstrapProvider)),
          data: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const EventPicker(),
              const SizedBox(height: 14),
              StatGrid(
                children: [
                  StatTile(icon: Icons.people_alt_rounded, label: 'Registered', value: stats?.value?.registered, color: context.colors.accent),
                  StatTile(icon: Icons.how_to_reg_rounded, label: 'Present today', value: stats?.value?.marked, color: context.colors.success),
                ],
              ),
            ],
          ),
        ),
        const SectionTitle('Quick actions'),
        ResponsiveGrid(
          compact: 1,
          medium: 2,
          expanded: 3,
          children: [
            _ActionTile(icon: Icons.how_to_reg_outlined, title: 'Attendance', subtitle: 'Search, mark present, undo', route: '/attendance'),
            _ActionTile(icon: Icons.person_add_alt_1_outlined, title: 'Register', subtitle: 'Add a new attendee', route: '/register'),
            if (me?.isStaff ?? false)
              _ActionTile(icon: Icons.phone_in_talk_outlined, title: 'My Calls', subtitle: 'Call contacts assigned to you', route: '/calls'),
            if (me?.isAdmin ?? false)
              _ActionTile(icon: Icons.admin_panel_settings_outlined, title: 'Admin', subtitle: 'People, calls, analytics, settings', route: '/admin'),
          ],
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

/// A big tappable shortcut on the Home screen.
class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.title, required this.subtitle, required this.route});
  final IconData icon;
  final String title, subtitle, route;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: kGapL, vertical: 10),
      leading: CircleAvatar(
        radius: 26,
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        foregroundColor: context.colors.brand,
        child: Icon(icon, size: 28),
      ),
      title: Text(title, style: Theme.of(context).textTheme.titleSmall),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => context.go(route),
    ),
  );
}
