import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

Future<void> shareLink(Map<String, dynamic> link) =>
    SharePlus.instance.share(ShareParams(text: '${link['title'] ?? ''}\n${link['url'] ?? ''}', subject: '${link['title'] ?? ''}'));

Future<void> copyLink(BuildContext context, Map<String, dynamic> link) async {
  await Clipboard.setData(ClipboardData(text: '${link['url'] ?? ''}'));
  if (context.mounted) showMessage(context, 'Link copied');
}

/// The icon and name of a link's type, and the word for what people send through it.
({IconData icon, String label, String unit}) linkKind(Map<String, dynamic> link) => switch (link['type']) {
  'Volunteer' => (icon: Icons.volunteer_activism_outlined, label: 'Volunteer', unit: 'registered'),
  'Feedback' => (icon: Icons.rate_review_outlined, label: 'Feedback', unit: 'responses'),
  _ => (icon: Icons.how_to_reg_outlined, label: 'Registration', unit: 'registered'),
};

/// One public link: what it is, who it is assigned to, how many people used it, and Share / Copy.
/// Admin passes [onEdit] and [onToggleOpen]; staff on Home see the same card without them.
class LinkCard extends StatelessWidget {
  const LinkCard({super.key, required this.link, this.onEdit, this.onToggleOpen});
  final Map<String, dynamic> link;
  final VoidCallback? onEdit;
  final ValueChanged<bool>? onToggleOpen;

  String get _title => '${link['title'] ?? ''}';
  String get _url => '${link['url'] ?? ''}';
  bool get _open => link['is_open'] == true;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final kind = linkKind(link);
    final assigned = '${link['assigned_name'] ?? ''}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(kGapM),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(_title, style: text.titleSmall)),
                if (onToggleOpen != null) Switch(value: _open, onChanged: onToggleOpen),
                if (onToggleOpen == null && !_open) const Chip(label: Text('Closed'), visualDensity: VisualDensity.compact),
              ],
            ),
            Wrap(
              spacing: kGapS,
              runSpacing: kGapXS,
              children: [
                Chip(
                  avatar: Icon(kind.icon, size: 18, color: context.colors.brand),
                  label: Text(kind.label),
                  visualDensity: VisualDensity.compact,
                ),
                Chip(label: Text('${link['event_name'] ?? ''}'), visualDensity: VisualDensity.compact),
                Chip(label: Text('${link['count'] ?? 0} ${kind.unit}'), visualDensity: VisualDensity.compact),
              ],
            ),
            if (onEdit != null)
              Padding(
                padding: const EdgeInsets.only(top: kGapXS),
                child: Text(assigned.isEmpty ? 'Not assigned to anyone' : 'Assigned to $assigned', style: text.bodyMedium),
              ),
            const SizedBox(height: kGapS),
            SelectableText(_url, style: text.bodyMedium),
            const SizedBox(height: kGapS),
            Wrap(
              spacing: kGapS,
              runSpacing: kGapS,
              children: [
                FilledButton.icon(
                  onPressed: () => shareLink(link),
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Share'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                ),
                OutlinedButton.icon(
                  onPressed: () => copyLink(context, link),
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copy'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                ),
                if (onEdit != null)
                  OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One of an event's two standard forms, shown inside the event card: name, how many answered, open/closed, URL, Share / Copy / Edit.
class EventLinkTile extends StatelessWidget {
  const EventLinkTile({super.key, required this.link, required this.onToggleOpen, required this.onEdit});
  final Map<String, dynamic> link;
  final ValueChanged<bool> onToggleOpen;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final kind = linkKind(link);
    final open = link['is_open'] == true;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(kGapM),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(kind.icon, color: context.colors.brand),
              const SizedBox(width: kGapS),
              Expanded(
                child: Text(
                  '${kind.label == 'Registration' ? 'Register' : kind.label} form  •  ${link['count'] ?? 0} ${kind.unit}',
                  style: text.titleSmall,
                ),
              ),
              Switch(value: open, onChanged: onToggleOpen),
            ],
          ),
          Text(open ? 'Open: anyone with the link can fill it.' : 'Closed: the link shows "closed".', style: text.bodyMedium),
          const SizedBox(height: kGapS),
          SelectableText('${link['url'] ?? ''}', style: text.bodyMedium),
          const SizedBox(height: kGapS),
          Wrap(
            spacing: kGapS,
            runSpacing: kGapS,
            children: [
              FilledButton.icon(
                onPressed: () => shareLink(link),
                icon: const Icon(Icons.share_outlined),
                label: const Text('Share'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              ),
              OutlinedButton.icon(
                onPressed: () => copyLink(context, link),
                icon: const Icon(Icons.copy_outlined),
                label: const Text('Copy'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
              ),
              OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
