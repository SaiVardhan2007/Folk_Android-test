import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import '../../core/layout.dart';

class _Dest {
  const _Dest(this.route, this.label, this.icon, this.selectedIcon);
  final String route, label;
  final IconData icon, selectedIcon;
}

const _home = _Dest('/', 'Home', Icons.home_outlined, Icons.home_rounded);
const _attendance = _Dest('/attendance', 'Attendance', Icons.how_to_reg_outlined, Icons.how_to_reg_rounded);
const _register = _Dest('/register', 'Register', Icons.person_add_alt_1_outlined, Icons.person_add_alt_1_rounded);
const _calls = _Dest('/calls', 'Calls', Icons.phone_in_talk_outlined, Icons.phone_in_talk_rounded);
const _admin = _Dest('/admin', 'Admin', Icons.admin_panel_settings_outlined, Icons.admin_panel_settings_rounded);

/// App frame: bottom bar on phones, side rail on tablets and wide windows. Content always fills the remaining width.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authProvider).value;
    final dests = [_home, _attendance, _register, if (me?.isStaff ?? false) _calls, if (me?.isAdmin ?? false) _admin];
    var index = dests.lastIndexWhere((d) => d.route == '/' ? location == '/' : location.startsWith(d.route));
    if (index < 0) index = 0;
    final title = dests[index].label;
    final wide = context.isWide;

    void go(int i) => context.go(dests[i].route);

    return Scaffold(
      appBar: AppBar(
        title: Text(index == 0 ? 'FOLK Tracker' : title),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Account',
            icon: CircleAvatar(
              radius: 18,
              backgroundColor: kBrandTint,
              foregroundColor: kMaroon, // the avatar tint is light in both modes, so its letter stays the dark maroon
              child: Text((me?.name.isNotEmpty ?? false) ? me!.name[0].toUpperCase() : '?'),
            ),
            onSelected: (v) async {
              if (v == 'out') {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Sign out?'),
                    content: const Text('Check-ins waiting to sync stay on this phone until you sign in again.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                      FilledButton(
                        style: FilledButton.styleFrom(minimumSize: const Size(100, 48)),
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('Sign out'),
                      ),
                    ],
                  ),
                );
                if (ok == true) ref.read(authProvider.notifier).signOut();
              }
            },
            itemBuilder: (c) => [
              PopupMenuItem(
                enabled: false,
                child: Text('${me?.name ?? ''}\n${me?.mob ?? ''}  •  ${me?.tag ?? ''}', style: Theme.of(c).textTheme.bodyMedium),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'out',
                child: ListTile(leading: Icon(Icons.logout), title: Text('Sign out'), contentPadding: EdgeInsets.zero),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: wide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: index,
                  onDestinationSelected: go,
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final d in dests) NavigationRailDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: Text(d.label)),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: child),
              ],
            )
          : child,
      bottomNavigationBar: wide
          ? null
          : AppBottomBar(items: [for (final d in dests) NavItem(d.label, d.icon, d.selectedIcon)], selected: index, onSelected: go),
    );
  }
}
