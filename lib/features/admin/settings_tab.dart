import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/widgets.dart';
import '../../core/layout.dart';
import '../../core/util.dart';
import '../auth/auth_controller.dart';
import '../printing/printer_service.dart';
import '../printing/printer_sheet.dart';
import '../printing/receipt_format.dart';
import '../printing/receipt_renderer.dart';
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
        const SizedBox(height: 16),
        Text('Receipt format', style: text.titleLarge),
        const SizedBox(height: 4),
        Text(
          'What the "Mark & Print Receipt" button prints on the Bluetooth or USB thermal printer. '
          'Everyone\'s phone uses this layout after it next opens the app.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: 12),
        if (s.hasValue)
          _ReceiptEditor(
            key: ValueKey(s.value!['receipt'].toString()),
            initial: ReceiptFormat.fromJson((s.value!['receipt'] as Map?)?.cast<String, dynamic>()),
            onSaved: () {
              ref.invalidate(_settingsProvider);
              ref.invalidate(bootstrapProvider);
            },
          ),
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

class _ReceiptEditor extends ConsumerStatefulWidget {
  const _ReceiptEditor({super.key, required this.initial, required this.onSaved});
  final ReceiptFormat initial;
  final VoidCallback onSaved;

  @override
  ConsumerState<_ReceiptEditor> createState() => _ReceiptEditorState();
}

class _ReceiptEditorState extends ConsumerState<_ReceiptEditor> {
  late final _title = TextEditingController(text: widget.initial.title);
  late final _subtitle = TextEditingController(text: widget.initial.subtitle);
  late final _footer = TextEditingController(text: widget.initial.footer);
  late bool _event = widget.initial.showEvent, _phone = widget.initial.showPhone, _time = widget.initial.showTime;
  late bool _count = widget.initial.showCount, _by = widget.initial.showMarkedBy;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _subtitle.dispose();
    _footer.dispose();
    super.dispose();
  }

  ReceiptFormat get _format => ReceiptFormat(
    title: _title.text.trim(),
    subtitle: _subtitle.text.trim(),
    footer: _footer.text.trim(),
    showEvent: _event,
    showPhone: _phone,
    showTime: _time,
    showCount: _count,
    showMarkedBy: _by,
  );

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref.read(adminRepoProvider).saveSettings({'receipt': _format.toJson()});
      widget.onSaved();
      if (mounted) showMessage(context, 'Receipt format saved');
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Prints a sample with the values on screen (saved or not), connecting the printer first if needed.
  Future<void> _test() async {
    final printer = ref.read(printerServiceProvider);
    if (!await ensurePrinter(context, printer)) return;
    setState(() => _busy = true);
    try {
      final image = await renderReceipt(
        _format,
        ReceiptData(name: 'Sample Name', mob: '9876543210', event: 'Sunday Programme', ts: istTimestamp(), count: 3, markedBy: 'Volunteer'),
      );
      await printer.printImage(image);
    } on PrinterException catch (e) {
      await printer.disconnect();
      if (mounted) showMessage(context, 'Could not print: ${e.message}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(kGapL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _title,
            maxLength: 60,
            decoration: const InputDecoration(labelText: 'Heading', helperText: 'Big text at the top, for example your centre name'),
          ),
          const SizedBox(height: kGapS),
          TextField(
            controller: _subtitle,
            maxLength: 60,
            decoration: const InputDecoration(labelText: 'Sub-heading'),
          ),
          const SizedBox(height: kGapS),
          TextField(
            controller: _footer,
            maxLength: 60,
            decoration: const InputDecoration(labelText: 'Footer message'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _phone,
            onChanged: (v) => setState(() => _phone = v),
            title: const Text('Show phone number'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _event,
            onChanged: (v) => setState(() => _event = v),
            title: const Text('Show event name'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _time,
            onChanged: (v) => setState(() => _time = v),
            title: const Text('Show date and time'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _count,
            onChanged: (v) => setState(() => _count = v),
            title: const Text('Show how many times attended'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _by,
            onChanged: (v) => setState(() => _by = v),
            title: const Text('Show who marked it'),
          ),
          const SizedBox(height: kGapS),
          FilledButton.icon(onPressed: _busy ? null : _save, icon: const Icon(Icons.save_outlined), label: const Text('Save receipt format')),
          const SizedBox(height: kGapS),
          OutlinedButton.icon(onPressed: _busy ? null : _test, icon: const Icon(Icons.print_outlined), label: const Text('Print a test receipt')),
        ],
      ),
    ),
  );
}
