import 'package:flutter/material.dart';

import 'layout.dart';
import 'models.dart';

/// The text of a dropdown field plus the ID of the value it shows.
/// [id] is '' while the text is not a value picked from the list (then the text itself is sent and the server matches or adds it).
class OptionController extends TextEditingController {
  String _id = '', _idTitle = '';

  /// The picked value's ID, as long as the text still shows that value.
  String get id => _id.isNotEmpty && optKey(text) == optKey(_idTitle) ? _id : '';

  void set(Opt o) {
    _id = o.id;
    _idTitle = o.title;
    text = o.title;
  }

  Opt get opt => Opt(id, text.trim());
}

/// The values picked in a multi-value dropdown (Skills, Interests).
class MultiOptionController extends ChangeNotifier {
  List<Opt> _values = const [];
  List<Opt> get values => _values;
  set values(List<Opt> v) {
    _values = List.unmodifiable(v);
    notifyListeners();
  }

  void add(Opt o) {
    if (!_values.any((x) => x.id == o.id)) values = [..._values, o];
  }

  void remove(Opt o) => values = _values.where((x) => x.id != o.id).toList();
}

Opt? _match(List<Opt> options, String text) {
  final k = optKey(text);
  if (k.isEmpty) return null;
  for (final o in options) {
    if (optKey(o.title) == k) return o;
  }
  return null;
}

Iterable<Opt> _filter(List<Opt> options, String text, Set<String> skip) {
  final q = text.trim().toLowerCase();
  final k = optKey(text);
  return options.where(
    (o) => !skip.contains(o.id) && (q.isEmpty || o.title.toLowerCase().contains(q) || (k.isNotEmpty && optKey(o.title).contains(k))),
  );
}

/// A dropdown you can type into (College / Company, Branch). Typing filters the list.
/// When the typed text is not in the list, a small Add button appears next to the field and adds it to the list for everyone.
class OptionPicker extends StatelessWidget {
  const OptionPicker({super.key, required this.controller, required this.label, required this.options, required this.onAdd, this.icon});
  final OptionController controller;
  final String label;
  final IconData? icon;
  final List<Opt> options;
  final Future<Opt?> Function(String title) onAdd;

  @override
  Widget build(BuildContext context) => _PickerField(
    controller: controller,
    label: label,
    icon: icon,
    options: options,
    onAdd: onAdd,
    picked: () => controller.id.isNotEmpty,
    onSelected: controller.set,
    onCleared: () => controller.set(Opt.none),
  );
}

/// Several values from one list (Skills, Interests): pick or add values, each shows as a chip that can be removed.
class MultiOptionPicker extends StatefulWidget {
  const MultiOptionPicker({super.key, required this.controller, required this.label, required this.options, this.onAdd, this.icon});
  final MultiOptionController controller;
  final String label;
  final IconData? icon;
  final List<Opt> options;

  /// Null = no Add button (used where values are only chosen, such as filters).
  final Future<Opt?> Function(String title)? onAdd;

  @override
  State<MultiOptionPicker> createState() => _MultiOptionPickerState();
}

class _MultiOptionPickerState extends State<MultiOptionPicker> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _pick(Opt o) {
    widget.controller.add(o);
    _text.clear();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final values = widget.controller.values;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _PickerField(
            controller: _text,
            label: widget.label,
            icon: widget.icon,
            options: widget.options,
            skip: {for (final v in values) v.id},
            onAdd: widget.onAdd,
            picked: () => false,
            onSelected: _pick,
            onCleared: _text.clear,
          ),
          if (values.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: kGapS),
              child: Wrap(
                spacing: kGapS,
                runSpacing: kGapS,
                children: [for (final v in values) InputChip(label: Text(v.title), onDeleted: () => widget.controller.remove(v))],
              ),
            ),
        ],
      );
    },
  );
}

/// The shared field: type-ahead list under the field, a clear button, and the small Add button when nothing matches.
class _PickerField extends StatefulWidget {
  const _PickerField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.options,
    required this.onAdd,
    required this.picked,
    required this.onSelected,
    required this.onCleared,
    this.skip = const {},
  });
  final TextEditingController controller;
  final String label;
  final IconData? icon;
  final List<Opt> options;
  final Set<String> skip;
  final Future<Opt?> Function(String title)? onAdd;

  /// True when the text already shows a picked value (so Add is not offered even before the list refreshes).
  final bool Function() picked;
  final ValueChanged<Opt> onSelected;
  final VoidCallback onCleared;

  @override
  State<_PickerField> createState() => _PickerFieldState();
}

class _PickerFieldState extends State<_PickerField> {
  final _focus = FocusNode();
  bool _adding = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final t = widget.controller.text.trim();
    if (t.isEmpty || _adding) return;
    setState(() => _adding = true);
    final o = await widget.onAdd!(t);
    if (!mounted) return;
    setState(() => _adding = false);
    if (o != null) widget.onSelected(o);
  }

  void _submitted(String t) {
    final m = _match(widget.options, t);
    if (m != null) {
      widget.onSelected(m);
    } else if (t.trim().isNotEmpty) {
      _add();
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => ValueListenableBuilder<TextEditingValue>(
      valueListenable: widget.controller,
      builder: (context, v, _) {
        final t = v.text.trim();
        final canAdd = widget.onAdd != null && t.isNotEmpty && !widget.picked() && _match(widget.options, t) == null;
        return Row(
          children: [
            Expanded(
              child: RawAutocomplete<Opt>(
                textEditingController: widget.controller,
                focusNode: _focus,
                displayStringForOption: (o) => o.title,
                optionsBuilder: (value) => _filter(widget.options, value.text, widget.skip),
                onSelected: widget.onSelected,
                fieldViewBuilder: (context, c, f, _) => TextFormField(
                  controller: c,
                  focusNode: f,
                  textCapitalization: TextCapitalization.words,
                  onFieldSubmitted: _submitted,
                  decoration: InputDecoration(
                    labelText: widget.label,
                    prefixIcon: widget.icon == null ? null : Icon(widget.icon),
                    suffixIcon: t.isEmpty
                        ? IconButton(tooltip: 'Show list', icon: const Icon(Icons.arrow_drop_down), onPressed: f.requestFocus)
                        : IconButton(tooltip: 'Clear', icon: const Icon(Icons.close), onPressed: widget.onCleared),
                  ),
                ),
                optionsViewBuilder: (context, select, options) => Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: 280, maxWidth: box.maxWidth),
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (context, i) {
                          final o = options.elementAt(i);
                          return ListTile(title: Text(o.title), onTap: () => select(o));
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (canAdd)
              Padding(
                padding: const EdgeInsets.only(left: kGapXS),
                child: _adding
                    ? const Padding(
                        padding: EdgeInsets.all(kGapS),
                        child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : TextButton.icon(
                        onPressed: _add,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: kGapS),
                        ),
                      ),
              ),
          ],
        );
      },
    ),
  );
}
