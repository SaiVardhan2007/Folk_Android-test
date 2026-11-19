import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/widgets.dart';
import '../../core/layout.dart';
import '../auth/auth_controller.dart';
import '../printing/printer_service.dart';
import '../printing/printer_sheet.dart';
import '../printing/receipt_format.dart';
import '../printing/receipt_renderer.dart';
import 'admin_repo.dart';
import 'logs_screen.dart';
import 'templates_editor.dart';

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
        Card(
          child: ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Activity log'),
            subtitle: const Text('Everything every user, coordinator and admin has done'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(builder: (_) => const LogsScreen())),
          ),
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
          'Two kinds of message: automatic messages the server sends (welcome and coordinator alert), and the text a coordinator sends with the Send Message button.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(kGapL),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Automatic messages', style: text.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'WhatsApp only delivers automatic messages from templates approved in your WhatsApp Business account, so the wording itself is edited there. '
                  'Type each template\'s name exactly as it is in that account to choose which one is sent.',
                  style: text.bodyMedium,
                ),
                const SizedBox(height: 12),
                if (s.hasValue) ...[
                  _TemplateName(
                    key: ValueKey('welcome_${s.value!['welcome_template']}'),
                    label: 'Welcome message template',
                    hint: 'Sent to a new contact. Fields in order: name, event, venue, map link, call number',
                    setting: 'welcome_template',
                    value: '${s.value!['welcome_template'] ?? ''}',
                    onSave: (k, v) => _setText(context, ref, k, v),
                  ),
                  const SizedBox(height: 12),
                  _TemplateName(
                    key: ValueKey('attendance_${s.value!['attendance_template']}'),
                    label: 'Coordinator alert template',
                    hint: 'Sent to the coordinator when their contact attends. Same five fields as the welcome template',
                    setting: 'attendance_template',
                    value: '${s.value!['attendance_template'] ?? ''}',
                    onSave: (k, v) => _setText(context, ref, k, v),
                  ),
                ] else
                  const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(kGapL),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Send Message button', style: text.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Type the messages coordinators can send from a call card. The selected one is sent after "Hare Krishna <name>". You can use {name} inside it.',
                  style: text.bodyMedium,
                ),
                const SizedBox(height: 12),
                const TemplatesEditor(),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Receipt format', style: text.titleLarge),
        const SizedBox(height: 4),
        Text(
          'What the "Mark & Print Receipt" button prints on the Bluetooth or USB thermal printer. '
          'Type the receipt exactly as you want it; everyone\'s phone uses it after it next opens the app.',
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
  const _TemplateName({super.key, required this.label, required this.hint, required this.setting, required this.value, required this.onSave});
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
  late final _text = TextEditingController(text: widget.initial.layout);
  late bool _logo = widget.initial.showLogo;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  ReceiptFormat get _format => ReceiptFormat(text: _text.text.trim(), showLogo: _logo);

  static const _sample = ReceiptData(
    name: 'Sample Name',
    mob: '9876543210',
    event: 'Saturday Satsang',
    ts: '2026-11-21 17:45:00',
    count: 3,
    markedBy: 'Volunteer',
  );

  /// Puts `s` where the cursor is (or at the end).
  void _insert(String s) {
    final t = _text.text;
    final sel = _text.selection;
    final start = sel.isValid ? sel.start : t.length;
    final end = sel.isValid ? sel.end : t.length;
    _text.value = TextEditingValue(
      text: t.replaceRange(start, end, s),
      selection: TextSelection.collapsed(offset: start + s.length),
    );
  }

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

  /// Shows the receipt as it will print, with sample details.
  Future<void> _preview() async {
    setState(() => _busy = true);
    try {
      final image = await renderReceipt(_format, _sample);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('How it will print'),
          content: SingleChildScrollView(
            child: Container(
              color: Colors.white,
              child: RawImage(image: image, width: 384, fit: BoxFit.fitWidth),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Close'))],
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Prints a sample with the text on screen (saved or not), connecting the printer first if needed.
  Future<void> _test() async {
    final printer = ref.read(printerServiceProvider);
    if (!await ensurePrinter(context, printer)) return;
    setState(() => _busy = true);
    try {
      await printer.printImage(await renderReceipt(_format, _sample));
    } on PrinterException catch (e) {
      await printer.disconnect();
      if (mounted) showMessage(context, 'Could not print: ${e.message}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(kGapL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Tap a field to add it where the cursor is:', style: text.bodyMedium),
            const SizedBox(height: kGapS),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [for (final f in kReceiptFields) ActionChip(label: Text(f.label), onPressed: () => _insert('{${f.key}}'))],
            ),
            const SizedBox(height: kGapM),
            TextField(
              controller: _text,
              minLines: 10,
              maxLines: 24,
              maxLength: 800,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Receipt text', alignLabelWithHint: true),
            ),
            const SizedBox(height: kGapS),
            Text(
              'One line here is one line on paper. Write fields in curly brackets, for example "Flower packets for {name} ({phone})". '
              'Start a line with "# " for big bold text, "## " for bold, "~ " to centre it, or write --- alone on a line for a dotted line. '
              'A line is left out when all its fields are empty.',
              style: text.bodyMedium,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _logo,
              onChanged: (v) => setState(() => _logo = v),
              title: const Text('Print the FOLK logo at the top'),
            ),
            const SizedBox(height: kGapS),
            FilledButton.icon(onPressed: _busy ? null : _save, icon: const Icon(Icons.save_outlined), label: const Text('Save receipt format')),
            const SizedBox(height: kGapS),
            OutlinedButton.icon(onPressed: _busy ? null : _preview, icon: const Icon(Icons.visibility_outlined), label: const Text('Preview')),
            if (!kIsWeb) ...[
              // thermal printers are reached over Bluetooth/USB, only in the Android app
              const SizedBox(height: kGapS),
              OutlinedButton.icon(onPressed: _busy ? null : _test, icon: const Icon(Icons.print_outlined), label: const Text('Print a test receipt')),
            ],
            TextButton(
              onPressed: _busy ? null : () => setState(() => _text.text = const ReceiptFormat().layout),
              child: const Text('Start again from the standard receipt'),
            ),
          ],
        ),
      ),
    );
  }
}
