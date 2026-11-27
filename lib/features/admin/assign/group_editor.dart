import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/layout.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../admin_repo.dart';
import 'assign_models.dart';
import 'assign_widgets.dart';

/// Edits one group in two small steps: 1) which contacts, 2) which coordinators and how. "Everyone else" skips step 1.
/// Works on a copy; the caller gets the finished group back only when the admin taps "Save group".
class GroupEditorPage extends ConsumerStatefulWidget {
  const GroupEditorPage({
    super.key,
    required this.group,
    required this.title,
    required this.rest,
    required this.draft,
    required this.callers,
    this.others = const [],
  });
  final GroupDraft group;
  final String title;
  final bool rest;
  final AssignDraft draft;
  final List<Map<String, dynamic>> callers;

  /// The other groups. A contact may be in only one group, so this group must not share any contact with them.
  final List<GroupDraft> others;
  @override
  ConsumerState<GroupEditorPage> createState() => _GroupEditorPageState();
}

class _GroupEditorPageState extends ConsumerState<GroupEditorPage> {
  String? _clash;
  bool _checking = false;

  late final GroupDraft _g = _copy(widget.group);
  late int _step = widget.rest ? 1 : 0;

  static GroupDraft _copy(GroupDraft g) {
    final c = GroupDraft(filters: [for (final f in g.filters) f.copy()])
      ..keepPrevious = g.keepPrevious
      ..leave = g.leave;
    for (final e in g.coords.entries) {
      c.coords[e.key] = CoordPick(e.value.mob, e.value.name, min: e.value.min, max: e.value.max);
    }
    return c;
  }

  /// Saves only when no contact of this group is also in another group.
  Future<void> _save() async {
    if (widget.rest) return Navigator.pop(context, _g);
    setState(() {
      _checking = true;
      _clash = null;
    });
    try {
      final r = await ref.read(adminRepoProvider).assignGroupSizes({
        ...widget.draft.planBody(),
        'groups': [for (final o in widget.others) o.toJson(), _g.toJson()],
      });
      final mine = widget.others.length;
      for (final o in (r['overlaps'] as List)) {
        if (o['b'] == mine) {
          if (mounted) {
            setState(
              () => _clash = '${o['count']} contacts are also in Group ${(o['a'] as int) + 1}. Change the filters so no contact is in two groups.',
            );
          }
          return;
        }
      }
      if (mounted) Navigator.pop(context, _g);
    } on ApiException catch (e) {
      if (mounted) setState(() => _clash = e.message);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final second = _step == 1;
    final steps = widget.rest ? 1 : 2;
    final n = widget.rest ? 1 : _step + 1;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: PageBody(
        children: [
          if (!widget.rest) ...[Text('Step $n of $steps', style: Theme.of(context).textTheme.bodyMedium), const SizedBox(height: kGapS)],
          if (!second) ...[
            const StepHeader(title: 'Which contacts are in this group?'),
            FilterEditor(
              filters: _g.filters,
              outer: widget.draft.filters,
              startAll: false,
              poolBody: widget.draft.poolBody(),
              onChanged: () => setState(() => _clash = null),
            ),
          ] else ...[
            StepHeader(title: widget.rest ? 'Who gets everyone else?' : 'Who gets these contacts?'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Leave them unassigned'),
              value: _g.leave,
              onChanged: (v) => setState(() => _g.leave = v),
            ),
            if (!_g.leave) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Same coordinator as before'),
                value: _g.keepPrevious,
                onChanged: (v) => setState(() => _g.keepPrevious = v),
              ),
              const Divider(),
              CoordinatorPicker(callers: widget.callers, group: _g, onChanged: () => setState(() {})),
            ],
            if (_clash != null) ...[
              const SizedBox(height: kGapM),
              StatusBanner(icon: Icons.error_outline, color: context.colors.danger, text: _clash!),
            ],
          ],
        ],
      ),
      bottomNavigationBar: WizardBar(
        onBack: second && !widget.rest ? () => setState(() => _step = 0) : null,
        nextLabel: second ? 'Save group' : 'Next',
        onNext: !second
            ? (_g.filters.isEmpty ? null : () => setState(() => _step = 1))
            : _g.ready && !_checking
            ? _save
            : null,
      ),
    );
  }
}

/// The bottom bar of every wizard screen: Back on the left, the main action on the right.
class WizardBar extends StatelessWidget {
  const WizardBar({super.key, this.onBack, required this.nextLabel, required this.onNext, this.note});
  final VoidCallback? onBack, onNext;
  final String nextLabel;
  final String? note;
  @override
  Widget build(BuildContext context) => Material(
    elevation: 8,
    color: Theme.of(context).colorScheme.surface,
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(kPagePadding, kGapM, kPagePadding, kGapM),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (note != null)
              Padding(
                padding: const EdgeInsets.only(bottom: kGapS),
                child: Text(note!, style: Theme.of(context).textTheme.bodyMedium),
              ),
            Row(
              children: [
                if (onBack != null) ...[
                  Expanded(
                    child: OutlinedButton(onPressed: onBack, child: const Text('Back')),
                  ),
                  const SizedBox(width: kGapM),
                ],
                Expanded(
                  flex: 2,
                  child: FilledButton(onPressed: onNext, child: Text(nextLabel)),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
