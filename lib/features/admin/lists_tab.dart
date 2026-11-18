import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/layout.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'admin_repo.dart';
import 'registrations_screen.dart';

/// Admin → Lists: always-open contact lists (e.g. Feedback, Contacts Register). They are not events: no "current", no attendance day.
class ListsTab extends ConsumerStatefulWidget {
  const ListsTab({super.key});
  @override
  ConsumerState<ListsTab> createState() => _ListsTabState();
}

class _ListsTabState extends ConsumerState<ListsTab> with AutomaticKeepAliveClientMixin {
  bool _busy = false;

  @override
  bool get wantKeepAlive => true;

  Future<void> _add() async {
    final code = TextEditingController();
    final name = TextEditingController();
    final key = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Add a contact list'),
        content: Form(
          key: key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'List name'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: code,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Short code', helperText: 'Letters and numbers, e.g. FEEDBACK'),
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
    if (ok == true) {
      setState(() => _busy = true);
      try {
        await ref.read(adminRepoProvider).addEvent(code.text.trim(), name.text.trim(), isList: true);
        ref.invalidate(bootstrapProvider);
        if (mounted) showMessage(context, 'List added');
      } on ApiException catch (e) {
        if (mounted) showMessage(context, e.message, error: true);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
    code.dispose();
    name.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final boot = ref.watch(bootstrapProvider);
    final text = Theme.of(context).textTheme;
    return PageBody(
      onRefresh: () async => ref.refresh(bootstrapProvider.future),
      children: [
        FilledButton.icon(onPressed: _busy ? null : _add, icon: const Icon(Icons.add), label: const Text('Add list')),
        const SizedBox(height: kGapS),
        Text(
          'Lists stay open all the time. Use them to keep a standing set of contacts, then assign them for calls in the Calls tab.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: kGapM),
        boot.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) =>
              ErrorView(message: e is ApiException ? e.message : 'Could not load lists.', onRetry: () => ref.invalidate(bootstrapProvider)),
          data: (b) => b.lists.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(child: Text('No lists yet.', style: text.bodyMedium)),
                )
              : Column(
                  children: [
                    for (final l in b.lists)
                      Padding(
                        padding: const EdgeInsets.only(bottom: kGapS),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l.name, style: text.titleSmall),
                                Text('Code: ${l.code}', style: text.bodyMedium),
                                const SizedBox(height: 12),
                                FilledButton.tonalIcon(
                                  onPressed: () => Navigator.of(context, rootNavigator: true).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => RegistrationsScreen(eventCode: l.code, eventName: l.name),
                                    ),
                                  ),
                                  icon: const Icon(Icons.how_to_reg_outlined),
                                  label: const Text('Contacts'),
                                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
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
