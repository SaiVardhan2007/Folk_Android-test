import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/auth_controller.dart';
import 'layout.dart';
import 'theme.dart';

void showMessage(BuildContext context, String message, {bool error = false}) {
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? scheme.error : null,
        duration: Duration(seconds: error ? 5 : 3),
      ),
    );
}

/// Standard page body: full width, small side padding, scrolls, pull-to-refresh optional.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.onRefresh, this.controller, this.bottomSpace = 24});
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final ScrollController? controller;
  final double bottomSpace;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(kPagePadding, 12, kPagePadding, bottomSpace),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: children,
    );
    return onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh!, child: list);
  }
}

/// Form fields: one column on phones, two on tablets and laptops.
class FieldGrid extends StatelessWidget {
  const FieldGrid({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => children.length == 1
      ? children
            .first // a lone field takes the full row instead of half of it
      : ResponsiveGrid(compact: 1, medium: 2, expanded: 2, spacing: kGapM + 2, children: children);
}

/// A number with a label ("12 Registered"). The single tile used for every statistic in the app.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, required this.color, this.icon, this.onTap});
  final String label;
  final Object? value;
  final Color color;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(kGapL),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                Container(
                  padding: const EdgeInsets.all(kGapS),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, color: color, size: 26),
                ),
                const SizedBox(height: kGapM),
              ],
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text('${value ?? '–'}', style: text.headlineMedium?.copyWith(color: color)),
              ),
              Text(label, style: text.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small square statistic (number over label) for tight headers. Use inside [StatStrip].
class MiniStat extends StatelessWidget {
  const MiniStat({super.key, required this.label, required this.value, required this.color, this.onTap});
  final String label;
  final Object? value;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(kGapXS + 2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${value ?? '–'}',
                  style: text.titleLarge?.copyWith(color: color, fontWeight: FontWeight.w700),
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label, maxLines: 1, style: text.labelSmall),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One row of equal SQUARE statistics ([MiniStat]), on every screen size.
class StatStrip extends StatelessWidget {
  const StatStrip({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) const SizedBox(width: kGapS),
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 96),
            child: AspectRatio(aspectRatio: 1, child: children[i]),
          ),
        ),
      ],
    ],
  );
}

/// A row of statistics: 2 per row on phones, 4 on tablets and laptops.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => ResponsiveGrid(compact: 2, medium: 4, expanded: 4, children: children);
}

/// Content of a bottom sheet: side padding, scrolls, and lifts above the keyboard.
class SheetBody extends StatelessWidget {
  const SheetBody({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(kPagePadding, 0, kPagePadding, MediaQuery.viewInsetsOf(context).bottom + kGapL),
    child: SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: children),
    ),
  );
}

/// One destination of the bottom bar.
class NavItem {
  const NavItem(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon, selectedIcon;
}

/// Bottom navigation made of real buttons: each tab is ONE tappable tile (icon and label together),
/// light background, a visible border, and a filled saffron look when selected.
class AppBottomBar extends StatelessWidget {
  const AppBottomBar({super.key, required this.items, required this.selected, required this.onSelected});
  final List<NavItem> items;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Material(
      color: scheme.surfaceContainerLow,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(kGapS, kGapS, kGapS, kGapS),
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(width: kGapS - 2),
                  Expanded(
                    child: _NavButton(item: items[i], selected: i == selected, onTap: () => onSelected(i), text: text, scheme: scheme),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.selected, required this.onTap, required this.text, required this.scheme});
  final NavItem item;
  final bool selected;
  final VoidCallback onTap;
  final TextTheme text;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? scheme.onPrimary : scheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: Material(
        color: selected ? scheme.primary : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? scheme.primary : scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: kGapS, horizontal: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(selected ? item.selectedIcon : item.icon, color: fg, size: 26),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      item.label,
                      maxLines: 1,
                      style: text.labelSmall?.copyWith(
                        color: fg,
                        fontSize: 12.5 * kTextScale,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The FOLK logo. Always on a white tile so it reads the same in light and dark mode.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.height = 96});
  final double height;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: kGapXL, vertical: kGapM),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
    child: Image.asset('assets/images/folk_logo.png', height: height, fit: BoxFit.contain, semanticLabel: 'FOLK Exclusive'),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 8),
    child: Row(
      children: [
        Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium)),
        ?trailing,
      ],
    ),
  );
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_outlined, size: 56, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
          if (onRetry != null) ...[const SizedBox(height: 16), FilledButton.tonal(onPressed: onRetry, child: const Text('Try again'))],
        ],
      ),
    ),
  );
}

class StatusBanner extends StatelessWidget {
  const StatusBanner({super.key, required this.icon, required this.text, this.color, this.action});
  final IconData icon;
  final String text;
  final Color? color;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final c = color ?? context.colors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, color: c),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
          ?action,
        ],
      ),
    );
  }
}

/// Dropdown to choose the event (shared by Home, Attendance, Register, Analytics).
class EventPicker extends ConsumerWidget {
  const EventPicker({super.key, this.label = 'Event'});
  final String label;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boot = ref.watch(bootstrapProvider).value;
    final selected = ref.watch(selectedEventProvider);
    final events = boot?.events ?? const [];
    if (events.isEmpty) return const SizedBox.shrink();
    return DropdownButtonFormField<String>(
      key: ValueKey(selected),
      initialValue: events.any((e) => e.code == selected) ? selected : events.first.code,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.event_outlined)),
      items: [
        for (final e in events)
          DropdownMenuItem(
            value: e.code,
            child: Text(e.name, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) => v == null ? null : ref.read(selectedEventProvider.notifier).select(v),
    );
  }
}

/// Simple labelled dropdown that allows "none".
class OptionDropdown extends StatelessWidget {
  const OptionDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.labelOf,
    this.allowNone = true,
    this.icon,
  });
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final String Function(String)? labelOf;
  final bool allowNone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    key: ValueKey('$label-$value'),
    initialValue: options.contains(value) ? value : (allowNone ? '' : null),
    isExpanded: true,
    decoration: InputDecoration(labelText: label, prefixIcon: icon == null ? null : Icon(icon)),
    items: [
      if (allowNone) const DropdownMenuItem(value: '', child: Text('—')),
      for (final o in options) DropdownMenuItem(value: o, child: Text(labelOf?.call(o) ?? o)),
    ],
    onChanged: (v) => onChanged(v ?? ''),
  );
}

/// A titled block of "label: value" lines (used for a person's details). Rows with an empty value are hidden;
/// a block with no rows disappears.
class DetailSection extends StatelessWidget {
  const DetailSection({super.key, required this.title, required this.rows});
  final String title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final r in rows)
        if (r.$2.trim().isNotEmpty) r,
    ];
    if (shown.isEmpty) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: kGapM),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(kGapL),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: text.labelLarge?.copyWith(color: context.colors.brand)),
            const SizedBox(height: kGapS),
            for (final r in shown)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: kGapXS),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 128,
                      child: Text(r.$1, style: text.bodyMedium?.copyWith(color: Theme.of(context).hintColor)),
                    ),
                    Expanded(child: SelectableText(r.$2, style: text.bodyLarge)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
