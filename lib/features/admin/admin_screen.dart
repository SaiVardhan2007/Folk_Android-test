import 'package:flutter/material.dart';

import 'analytics_tab.dart';
import 'calls_admin_tab.dart';
import 'events_tab.dart';
import 'settings_tab.dart';

/// Admin area: Calls (the first and default tab), Analytics, Events and Settings. People has its own place in the main navigation.
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 4,
    child: Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(icon: Icon(Icons.phone_in_talk_outlined), text: 'Calls'),
              Tab(icon: Icon(Icons.insights_outlined), text: 'Analytics'),
              Tab(icon: Icon(Icons.event_outlined), text: 'Events'),
              Tab(icon: Icon(Icons.tune_outlined), text: 'Settings'),
            ],
          ),
        ),
        const Expanded(child: TabBarView(children: [CallsAdminTab(), AnalyticsTab(), EventsTab(), SettingsTab()])),
      ],
    ),
  );
}
