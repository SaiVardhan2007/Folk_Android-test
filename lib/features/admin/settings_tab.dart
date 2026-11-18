import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'admin_repo.dart';

final _settingsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) => ref.read(adminRepoProvider).settings());

/// Admin → Settings: switches that change how the whole app behaves.
class SettingsTab extends ConsumerWidget {
  const SettingsTab({super.key});

  Future<void> _set(BuildContext context, WidgetRef ref, String key, bool value) async {
    try {
      await ref.read(adminRepoProvider).saveSettings({key: value});
      ref.invalidate(_settingsProvider);
      ref.invalidate(bootstrapProvider); // phones pick the change up on next start; this refreshes this phone now
    } on ApiException catch (e) {
      if (context.mounted) showMessage(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(_settingsProvider);
    final text = Theme.of(context).textTheme;
    return PageBody(
      onRefresh: () async => ref.invalidate(_settingsProvider),
      children: [
        Text('App settings', style: text.titleLarge),
        const SizedBox(height: 4),
        Text(
          'These switches apply to everyone using the app. Other phones pick up a change the next time they open the app.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: 12),
        s.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) =>
              ErrorView(message: e is ApiException ? e.message : 'Could not load settings.', onRetry: () => ref.invalidate(_settingsProvider)),
          data: (v) => Card(
            child: Column(
              children: [
                SwitchListTile(
                  value: v['offline_queue_enabled'] == true,
                  onChanged: (x) => _set(context, ref, 'offline_queue_enabled', x),
                  title: const Text('Offline check-in queue'),
                  subtitle: const Text('When there is no signal, save check-ins on the phone and send them automatically later.'),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: v['auto_approve_signups'] == true,
                  onChanged: (x) => _set(context, ref, 'auto_approve_signups', x),
                  title: const Text('Approve new sign-ups automatically'),
                  subtitle: const Text('Off: a new coordinator can sign in only after an admin enables the account (People → Awaiting approval).'),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: v['whatsapp_enabled'] == true,
                  onChanged: (x) => _set(context, ref, 'whatsapp_enabled', x),
                  title: const Text('WhatsApp message on new registration'),
                  subtitle: const Text('Sends the welcome message to the new contact and their FOLK Guide when someone is registered.'),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: v['notify_coordinator_attendance'] == true,
                  onChanged: (x) => _set(context, ref, 'notify_coordinator_attendance', x),
                  title: const Text('WhatsApp the coordinator when their contact attends'),
                  subtitle: const Text(
                    'The coordinator assigned to call a contact gets the contact\'s name, phone number and check-in time at once.',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('WhatsApp message formats', style: text.titleLarge),
        const SizedBox(height: 4),
        Text(
          'WhatsApp only delivers automatic messages from templates approved in your WhatsApp Business account. The wording is edited there; '
          'enter each template\'s name here to choose which one is sent.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: 12),
        if (s.hasValue) ...[
          _TemplateName(
            label: 'Welcome message template',
            hint: 'Parameters: name, event, venue, map link, call number',
            setting: 'welcome_template',
            value: '${s.value!['welcome_template'] ?? ''}',
            onSave: (k, v) => _setText(context, ref, k, v),
          ),
          const SizedBox(height: 12),
          _TemplateName(
            label: 'Coordinator attendance alert template',
            hint: 'Parameters: coordinator name, contact name, contact phone, time',
            setting: 'attendance_template',
            value: '${s.value!['attendance_template'] ?? ''}',
            onSave: (k, v) => _setText(context, ref, k, v),
          ),
        ],
      ],
    );
  }

  Future<void> _setText(BuildContext context, WidgetRef ref, String key, String value) async {
    try {
      await ref.read(adminRepoProvider).saveSettings({key: value});
      ref.invalidate(_settingsProvider);
      if (context.mounted) showMessage(context, 'Saved');
    } on ApiException catch (e) {
      if (context.mounted) showMessage(context, e.message, error: true);
    }
  }
}

class _TemplateName extends StatefulWidget {
  const _TemplateName({required this.label, required this.hint, required this.setting, required this.value, required this.onSave});
  final String label, hint, setting, value;
  final void Function(String key, String value) onSave;

  @override
  State<_TemplateName> createState() => _TemplateNameState();
}

class _TemplateNameState extends State<_TemplateName> {
  late final _c = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: TextField(
          controller: _c,
          autocorrect: false,
          decoration: InputDecoration(labelText: widget.label, helperText: widget.hint, helperMaxLines: 2),
        ),
      ),
      const SizedBox(width: 8),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: FilledButton(onPressed: () => widget.onSave(widget.setting, _c.text), child: const Text('Save')),
      ),
    ],
  );
}
