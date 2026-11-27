import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_android_app/core/models.dart';
import 'package:folk_android_app/core/option_picker.dart';

const _list = [Opt('a1', 'CBIT - Chaitanya Bharathi Institute of Technology'), Opt('a2', 'Cognizant'), Opt('a3', 'MGIT')];

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(16), child: child),
  ),
);

void main() {
  test('OptionController keeps the ID only while the text shows that value', () {
    final c = OptionController()..set(const Opt('a2', 'Cognizant'));
    expect(c.opt, const Opt('a2', 'Cognizant'));
    c.text = 'cognizant '; // same value apart from case/space
    expect(c.id, 'a2');
    c.text = 'Cognizant India';
    expect(c.opt, const Opt('', 'Cognizant India'));
  });

  test('optKey ignores case, spaces and punctuation', () {
    expect(optKey('C.B.I.T'), optKey('cbit'));
    expect(optKey('  Nxt  Wave '), optKey('NxtWave'));
  });

  testWidgets('Add shows only when the typed text is not in the list, and adds it', (tester) async {
    final c = OptionController();
    String? added;
    await tester.pumpWidget(
      _host(
        OptionPicker(
          controller: c,
          label: 'Company / College',
          options: _list,
          onAdd: (t) async {
            added = t;
            return Opt('new1', t);
          },
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField), 'mgit');
    await tester.pump();
    expect(find.text('Add'), findsNothing); // matches "MGIT"

    await tester.enterText(find.byType(TextFormField), 'Wipro');
    await tester.pump();
    expect(find.text('Add'), findsOneWidget);
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(added, 'Wipro');
    expect(c.opt, const Opt('new1', 'Wipro'));
    expect(find.text('Add'), findsNothing); // picked, even before the list refreshes
  });

  testWidgets('picking from the filtered list sets the ID', (tester) async {
    final c = OptionController();
    await tester.pumpWidget(_host(OptionPicker(controller: c, label: 'College', options: _list, onAdd: (_) async => null)));
    await tester.tap(find.byType(TextFormField));
    await tester.enterText(find.byType(TextFormField), 'chaitanya');
    await tester.pumpAndSettle();
    await tester.tap(find.text('CBIT - Chaitanya Bharathi Institute of Technology').last);
    await tester.pumpAndSettle();
    expect(c.id, 'a1');
  });

  testWidgets('multi picker adds chips and removes them', (tester) async {
    final c = MultiOptionController();
    await tester.pumpWidget(_host(MultiOptionPicker(controller: c, label: 'Skills', options: _list, onAdd: (_) async => null)));
    await tester.tap(find.byType(TextFormField));
    await tester.enterText(find.byType(TextFormField), 'cogn');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cognizant').last);
    await tester.pumpAndSettle();
    expect(c.values.map((o) => o.id), ['a2']);
    expect(find.byType(InputChip), findsOneWidget);
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(c.values, isEmpty);
  });
}
