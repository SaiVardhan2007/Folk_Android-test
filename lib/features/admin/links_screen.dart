import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/layout.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'admin_repo.dart';
import 'link_card.dart';

/// All public form links (admin). Invalidate after any change.
final linksProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) => ref.read(adminRepoProvider).links());

/// Opens the create/edit sheet. [eventCode] pre-selects the event for a new link.
Future<void> showLinkSheet(BuildContext context, WidgetRef ref, {Map<String, dynamic>? link, String eventCode = ''}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (_) => _LinkSheet(link: link, eventCode: eventCode),
  );
  if (saved == true) ref.invalidate(linksProvider);
}

/// Opens or closes a link for new responses.
Future<void> setLinkOpen(BuildContext context, WidgetRef ref, Map<String, dynamic> l, bool open) async {
  try {
    await ref.read(adminRepoProvider).updateLink('${l['slug']}', {'is_open': open});
    ref.invalidate(linksProvider);
  } on ApiException catch (e) {
    if (context.mounted) showMessage(context, e.message, error: true);
  }
}

/// Admin → Events → More links: every public form of one event (extra volunteer links, links assigned to a person, and the two standard forms).
class LinksScreen extends ConsumerWidget {
  const LinksScreen({super.key, this.eventCode = '', this.eventName = ''});
  final String eventCode, eventName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final links = ref.watch(linksProvider);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(eventName.isEmpty ? 'Public forms' : '$eventName forms')),
      body: PageBody(
        onRefresh: () async => ref.invalidate(linksProvider),
        children: [
          FilledButton.icon(
            onPressed: () => showLinkSheet(context, ref, eventCode: eventCode),
            icon: const Icon(Icons.add_link),
            label: const Text('New link'),
          ),
          const SizedBox(height: kGapS),
          const SizedBox(height: kGapM),
          links.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) =>
                ErrorView(message: e is ApiException ? e.message : 'Could not load links.', onRetry: () => ref.invalidate(linksProvider)),
            data: (all) {
              final list = [
                for (final l in all)
                  if (eventCode.isEmpty || l['event_code'] == eventCode) l,
              ];
              return list.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Center(child: Text('No links yet. Tap New link.', style: text.bodyMedium)),
                    )
                  : Column(
                      children: [
                        for (final l in list)
                          Padding(
                            padding: const EdgeInsets.only(bottom: kGapS),
                            child: LinkCard(
                              link: l,
                              onEdit: () => showLinkSheet(context, ref, link: l),
                              onToggleOpen: (v) => setLinkOpen(context, ref, l, v),
                            ),
                          ),
                      ],
                    );
            },
          ),
        ],
      ),
    );
  }
}

/// Create (no [link]) or edit a link. Type and event are fixed once created, because registrations belong to them.
class _LinkSheet extends ConsumerStatefulWidget {
  const _LinkSheet({this.link, this.eventCode = ''});
  final Map<String, dynamic>? link;
  final String eventCode;
  @override
  ConsumerState<_LinkSheet> createState() => _LinkSheetState();
}

class _LinkSheetState extends ConsumerState<_LinkSheet> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: '${widget.link?['title'] ?? ''}');
  late final _assigned = TextEditingController();
  late final _intro = TextEditingController(text: '${widget.link?['intro'] ?? ''}');
  late final _slots = TextEditingController(text: ((widget.link?['slots'] as List?) ?? const []).join('\n'));
  late final _services = TextEditingController(text: ((widget.link?['services'] as List?) ?? const []).join('\n'));
  late String _type = '${widget.link?['type'] ?? 'Registration'}';
  late String _event = '${widget.link?['event_code'] ?? widget.eventCode}';
  late bool _dinner = widget.link?['ask_dinner'] == true,
      _transport = widget.link?['ask_transport'] == true,
      _donation = widget.link?['ask_donation'] == true;
  bool _busy = false;

  bool get _editing => widget.link != null;

  @override
  void dispose() {
    _title.dispose();
    _assigned.dispose();
    _intro.dispose();
    _slots.dispose();
    _services.dispose();
    super.dispose();
  }

  List<String> _lines(TextEditingController c) => c.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final body = <String, dynamic>{
      'title': _title.text.trim(),
      'intro': _intro.text.trim(),
      if (!_editing || _assigned.text.trim().isNotEmpty || _clearAssigned) 'assigned_mob': _assigned.text.trim(),
      if (_type == 'Registration') ...{'ask_dinner': _dinner, 'ask_transport': _transport, 'ask_donation': _donation},
      if (_type == 'Volunteer') ...{'slots': _lines(_slots), 'services': _lines(_services)},
    };
    try {
      final repo = ref.read(adminRepoProvider);
      if (_editing) {
        await repo.updateLink('${widget.link!['slug']}', body);
      } else {
        await repo.createLink({...body, 'type': _type, 'event': _event});
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } catch (_) {
      if (mounted) showMessage(context, 'Could not save.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _clearAssigned = false;

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(bootstrapProvider).value?.events ?? const [];
    final current = '${widget.link?['assigned_name'] ?? ''}';
    return SheetBody(
      children: [
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_editing ? 'Edit link' : 'New registration link', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: kGapM),
              TextFormField(
                controller: _title,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Title (people see this)', prefixIcon: Icon(Icons.title)),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a title' : null,
              ),
              const SizedBox(height: kGapM),
              if (!_editing) ...[
                OptionDropdown(
                  label: 'Type',
                  value: _type,
                  options: const ['Registration', 'Volunteer'],
                  allowNone: false,
                  labelOf: (v) => v == 'Volunteer' ? 'Volunteer registration' : 'Event registration (new or existing person)',
                  icon: Icons.category_outlined,
                  onChanged: (v) => setState(() => _type = v),
                ),
                const SizedBox(height: kGapM),
                DropdownButtonFormField<String>(
                  initialValue: events.any((e) => e.code == _event) ? _event : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Event', prefixIcon: Icon(Icons.event_outlined)),
                  items: [for (final e in events) DropdownMenuItem(value: e.code, child: Text(e.name))],
                  onChanged: (v) => _event = v ?? '',
                  validator: (v) => (v == null || v.isEmpty) ? 'Choose an event' : null,
                ),
                const SizedBox(height: kGapM),
              ],
              TextFormField(
                controller: _assigned,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ \-]')), LengthLimitingTextInputFormatter(15)],
                decoration: InputDecoration(
                  labelText: 'Assign to (mobile number, optional)',
                  helperText: _editing && current.isNotEmpty && !_clearAssigned ? 'Now: $current' : null,
                  prefixIcon: const Icon(Icons.person_pin_outlined),
                  suffixIcon: _editing && current.isNotEmpty
                      ? IconButton(
                          tooltip: 'Remove assignment',
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() {
                            _clearAssigned = true;
                            _assigned.clear();
                          }),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: kGapM),
              TextFormField(
                controller: _intro,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Message shown on the page (optional)', prefixIcon: Icon(Icons.notes_outlined)),
              ),
              if (_type == 'Registration') ...[
                const SizedBox(height: kGapS),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _dinner,
                  onChanged: (v) => setState(() => _dinner = v),
                  title: const Text('Ask about dinner'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _transport,
                  onChanged: (v) => setState(() => _transport = v),
                  title: const Text('Ask about transport'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _donation,
                  onChanged: (v) => setState(() => _donation = v),
                  title: const Text('Ask about donation'),
                ),
              ] else if (_type == 'Volunteer') ...[
                const SizedBox(height: kGapM),
                TextFormField(
                  controller: _slots,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Time slots (one per line)',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.schedule_outlined),
                  ),
                ),
                const SizedBox(height: kGapM),
                TextFormField(
                  controller: _services,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Services (one per line)',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.volunteer_activism_outlined),
                  ),
                ),
              ],
              const SizedBox(height: kGapL),
              FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving...' : (_editing ? 'Save' : 'Create link'))),
            ],
          ),
        ),
      ],
    );
  }
}
