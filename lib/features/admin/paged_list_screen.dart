import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/layout.dart';
import '../../core/widgets.dart';

typedef PageLoader = Future<Map<String, dynamic>> Function(Map<String, String> filters, int page);

/// A full-screen list of server records, newest first: search box, optional filter chips, an optional header (totals),
/// pages of 50 loaded as you scroll, pull-to-refresh and an optional CSV export. Used by Registrations and the Activity log.
class PagedListScreen extends StatefulWidget {
  const PagedListScreen({
    super.key,
    required this.title,
    required this.load,
    required this.itemBuilder,
    this.header,
    this.export,
    this.fixedFilters = const {},
    this.chips = const {},
    this.searchLabel = 'Search',
    this.emptyText = 'Nothing here yet.',
  });

  final String title, searchLabel, emptyText;
  final PageLoader load;
  final Widget Function(BuildContext context, Map<String, dynamic> row) itemBuilder;

  /// Built from the first page's response (for totals).
  final Widget Function(BuildContext context, Map<String, dynamic> response)? header;
  final Future<void> Function(Map<String, String> filters)? export;

  /// Always sent (e.g. the chosen event).
  final Map<String, String> fixedFilters;

  /// Single-choice chips: filter key -> options (a leading "All" is added).
  final Map<String, List<String>> chips;

  @override
  State<PagedListScreen> createState() => _PagedListScreenState();
}

class _PagedListScreenState extends State<PagedListScreen> {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  Timer? _debounce;
  final Map<String, String> _chosen = {};
  final List<Map<String, dynamic>> _rows = [];
  Map<String, dynamic> _first = const {};
  int _page = 0, _generation = 0;
  bool _loading = false, _done = false, _exporting = false;
  String? _error;

  Map<String, String> get _filters => {
    ...widget.fixedFilters,
    for (final e in _chosen.entries)
      if (e.value.isNotEmpty) e.key: e.value,
    if (_search.text.trim().isNotEmpty) 'q': _search.text.trim(),
  };

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _fetch();
    });
    _fetch(reset: true);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _fetch({bool reset = false}) async {
    // A new search or filter (reset) always starts over; an answer to an older request is ignored when it arrives.
    if (!reset && (_loading || _done)) return;
    if (reset) {
      _page = 0;
      _done = false;
      _rows.clear();
    }
    final generation = reset ? ++_generation : _generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await widget.load(_filters, _page);
      if (!mounted || generation != _generation) return;
      final rows = ((r['rows'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final size = (r['page_size'] as num?)?.toInt() ?? 50;
      setState(() {
        if (_page == 0) _first = r;
        _page++;
        _rows.addAll(rows);
        _done = rows.length < size;
      });
    } on ApiException catch (e) {
      if (mounted && generation == _generation) setState(() => _error = e.message);
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _error = 'Could not load. Check your connection.');
    } finally {
      if (mounted && generation == _generation) setState(() => _loading = false);
    }
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      await widget.export!(_filters);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } catch (_) {
      if (mounted) showMessage(context, 'Could not share the file.', error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (widget.export != null)
            IconButton(
              tooltip: 'Share as CSV',
              onPressed: _exporting ? null : _export,
              icon: _exporting
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.ios_share),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _fetch(reset: true),
        child: ListView.builder(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(kPagePadding, 12, kPagePadding, 24),
          // Row 0 = search, filters and totals; then the records; then a footer (loading / error / end).
          itemCount: _rows.length + 2,
          itemBuilder: (context, i) {
            if (i == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(labelText: widget.searchLabel, prefixIcon: const Icon(Icons.search)),
                    onChanged: (_) {
                      _debounce?.cancel();
                      _debounce = Timer(const Duration(milliseconds: 400), () => _fetch(reset: true));
                    },
                  ),
                  for (final e in widget.chips.entries) ...[
                    const SizedBox(height: kGapS),
                    Wrap(
                      spacing: kGapS,
                      children: [
                        for (final o in ['', ...e.value])
                          ChoiceChip(
                            label: Text(o.isEmpty ? 'All' : o),
                            selected: (_chosen[e.key] ?? '') == o,
                            onSelected: (_) {
                              setState(() => _chosen[e.key] = o);
                              _fetch(reset: true);
                            },
                          ),
                      ],
                    ),
                  ],
                  if (widget.header != null && _first.isNotEmpty) ...[const SizedBox(height: kGapM), widget.header!(context, _first)],
                  const SizedBox(height: kGapM),
                ],
              );
            }
            if (i == _rows.length + 1) {
              if (_error != null) {
                return ErrorView(
                  message: _error!,
                  onRetry: () => _fetch(reset: _rows.isEmpty),
                );
              }
              if (_loading) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (_rows.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(child: Text(widget.emptyText, style: text.bodyMedium)),
                );
              }
              return const SizedBox(height: kGapM);
            }
            return widget.itemBuilder(context, _rows[i - 1]);
          },
        ),
      ),
    );
  }
}
