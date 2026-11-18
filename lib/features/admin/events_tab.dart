import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'admin_repo.dart';
import 'links_screen.dart';
import 'registrations_screen.dart';

class EventsTab extends ConsumerStatefulWidget {
  const EventsTab({super.key});
  @override
  ConsumerState<EventsTab> createState() => _EventsTabState();
}

class _EventsTabState extends ConsumerState<EventsTab> with AutomaticKeepAliveClientMixin {
  bool _busy = false;

  @override
  bool get wantKeepAlive => true;

  Future<void> _run(Future<void> Function() f, String done) async {
    setState(() => _busy = true);
    try {
      await f();
      ref.invalidate(bootstrapProvider);
      if (mounted) showMessage(context, done);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } catch (_) {
      if (mounted) showMessage(context, 'Something went wrong.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final code = TextEditingController();
    final name = TextEditingController();
    final key = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Add an event'),
        content: Form(
          key: key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Event name'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: code,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Short code', helperText: 'e.g. SUNDAY, YOUTH1 (letters and numbers)'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a code' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(100, 48)),
            onPressed: () => key.currentState!.validate() ? Navigator.pop(c, true) : null,
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (ok == true) await _run(() => ref.read(adminRepoProvider).addEvent(code.text.trim(), name.text.trim()), 'Event added');
    code.dispose();
    name.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final boot = ref.watch(bootstrapProvider);
    final text = Theme.of(context).textTheme;
    final repo = ref.read(adminRepoProvider);
    return PageBody(
      onRefresh: () async => ref.refresh(bootstrapProvider.future),
      children: [
        FilledButton.icon(onPressed: _busy ? null : _add, icon: const Icon(Icons.add), label: const Text('Add event')),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(builder: (_) => const LinksScreen())),
          icon: const Icon(Icons.add_link),
          label: const Text('Registration links'),
        ),
        const SizedBox(height: 8),
        Text('The "current" event is selected by default for everyone on Home, Attendance and Register.', style: text.bodyMedium),
        const SizedBox(height: 12),
        boot.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) =>
              ErrorView(message: e is ApiException ? e.message : 'Could not load events.', onRetry: () => ref.invalidate(bootstrapProvider)),
          data: (b) => Column(
            children: [
              for (final e in b.events)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text(e.name, style: text.titleSmall)),
                              if (e.isCurrent)
                                Chip(
                                  label: const Text('Current'),
                                  backgroundColor: context.colors.success.withValues(alpha: 0.15),
                                  side: BorderSide.none,
                                  avatar: Icon(Icons.check_circle, color: context.colors.success, size: 20),
                                ),
                            ],
                          ),
                          Text('Code: ${e.code}', style: text.bodyMedium),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              if (!e.isCurrent)
                                FilledButton.tonalIcon(
                                  onPressed: _busy ? null : () => _run(() => repo.setCurrentEvent(e.code), '${e.name} is now the current event'),
                                  icon: const Icon(Icons.flag_outlined),
                                  label: const Text('Make current'),
                                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                                ),
                              FilledButton.tonalIcon(
                                onPressed: () => Navigator.of(context, rootNavigator: true).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => RegistrationsScreen(eventCode: e.code, eventName: e.name),
                                  ),
                                ),
                                icon: const Icon(Icons.how_to_reg_outlined),
                                label: const Text('Registrations'),
                                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                              ),
                              OutlinedButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () => _run(
                                        () => repo.shareCsv('/reports/attendance', 'folk-attendance-${e.code}.csv', query: {'event': e.code}),
                                        'Attendance file ready',
                                      ),
                                icon: const Icon(Icons.ios_share),
                                label: const Text('Attendance CSV'),
                                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
