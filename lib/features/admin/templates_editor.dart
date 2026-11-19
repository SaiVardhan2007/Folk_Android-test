import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/widgets.dart';
import 'admin_repo.dart';

/// The "Send Message" texts a coordinator can send to a contact on WhatsApp. One is selected (sent by the button); you can add, edit and delete.
/// Shown in Admin → Settings and in the Calls tab.
class TemplatesEditor extends ConsumerStatefulWidget {
  const TemplatesEditor({super.key, this.onSaved});
  final VoidCallback? onSaved;

  @override
  ConsumerState<TemplatesEditor> createState() => _TemplatesEditorState();
}

class _TemplatesEditorState extends ConsumerState<TemplatesEditor> {
  final List<({TextEditingController head, TextEditingController body})> _rows = [];
  int _active = 0;
  bool _loading = true, _busy = false, _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final t = await ref.read(adminRepoProvider).templates();
      if (!mounted) return;
      setState(() {
        for (var i = 0; i < t.length; i++) {
          _rows.add((head: TextEditingController(text: '${t[i]['heading']}'), body: TextEditingController(text: '${t[i]['text']}')));
          if (t[i]['active'] == true) _active = i;
        }
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.head.dispose();
      r.body.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref.read(adminRepoProvider).saveTemplates([
        for (var i = 0; i < _rows.length; i++) {'heading': _rows[i].head.text, 'text': _rows[i].body.text, 'active': i == _active},
      ]);
      if (mounted) {
        showMessage(context, 'Saved. Coordinators get the selected message on their next refresh.');
        widget.onSaved?.call();
      }
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_loading) const Center(child: CircularProgressIndicator()),
        if (_failed) const Text('Could not load the messages. Pull down to refresh and try again.'),
        if (!_loading && !_failed && _rows.isEmpty) const Text('No message yet. Tap "Add a message" and write one.'),
        for (var i = 0; i < _rows.length; i++)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      RadioGroup<int>(
                        groupValue: _active,
                        onChanged: (v) => setState(() => _active = v ?? 0),
                        child: Radio<int>(value: i),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _rows[i].head,
                          decoration: const InputDecoration(labelText: 'Heading'),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => setState(() {
                          _rows.removeAt(i);
                          if (_active >= _rows.length) _active = 0;
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _rows[i].body,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Message'),
                  ),
                ],
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _rows.add((head: TextEditingController(text: 'Message'), body: TextEditingController()))),
            icon: const Icon(Icons.add),
            label: const Text('Add a message'),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton(onPressed: _busy || _loading ? null : _save, child: Text(_busy ? 'Saving…' : 'Save messages')),
      ],
    );
  }
}
