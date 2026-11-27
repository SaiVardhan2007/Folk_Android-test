import 'package:flutter_test/flutter_test.dart';
import 'package:folk_android_app/features/admin/assign/assign_models.dart';

void main() {
  test('plan body carries filters, groups and limits in the shape the server expects', () {
    final d = AssignDraft('EV1')..kind = AssignKind.assign;
    d.filters.add(FilterDraft('college', values: {'c1': 'CBIT'}));
    final g = GroupDraft(
      filters: [
        FilterDraft('branch', values: {'': '(Empty)'}),
      ],
    );
    g.coords['9876543210'] = CoordPick('9876543210', 'Ravi', min: 3, max: 10);
    d.groups.add(g);
    d.rest.leave = true;
    final b = d.planBody();
    expect(b['kind'], 'assign');
    expect((b['filters'] as List).last, {
      'field': 'college',
      'mode': 'only',
      'values': ['c1'],
    });
    final gj = (b['groups'] as List).single as Map;
    expect(gj['coordinators'], [
      {'mob': '9876543210', 'min': 3, 'max': 10},
    ]);
    expect((b['rest'] as Map)['leave'], true);
  });

  test('everyone starts selected except women; coordinators start at 20 to 50', () {
    final d = AssignDraft('EV1');
    expect(d.filters.single.values.keys, ['M', '']);
    final c = CoordPick('1', 'A');
    expect((c.min, c.max), (20, 50));
  });

  test('a group needs contacts chosen, and coordinators or "leave unassigned"', () {
    final g = GroupDraft();
    expect(g.readyAsGroup, false);
    g.filters.add(FilterDraft('college', values: {'c1': 'CBIT'}));
    expect(g.readyAsGroup, false);
    g.coords['1'] = CoordPick('1', 'A');
    expect(g.readyAsGroup, true);
  });

  test('reassigning unstarted calls has just two steps', () {
    expect(stepsFor(AssignKind.move, reassign: true), [AssignStep.to, AssignStep.review]);
  });

  test('a group is ready only with coordinators or when left unassigned', () {
    final g = GroupDraft();
    expect(g.ready, false);
    g.leave = true;
    expect(g.ready, true);
  });

  test('batches never exceed the size and keep each coordinator apart', () {
    final plan = {
      'moves': [
        {'coordinator': 'a', 'persons': List.generate(120, (i) => 'p$i')},
        {
          'coordinator': 'b',
          'persons': ['x'],
        },
      ],
    };
    final b = makeBatches(plan, size: 50);
    expect(b.map((x) => (x['persons'] as List).length), [50, 50, 20, 1]);
    expect(b.last['coordinator'], 'b');
  });

  test('each kind has its own steps and always starts and ends sensibly', () {
    expect(stepsFor(null), [AssignStep.start]);
    for (final k in AssignKind.values) {
      expect(stepsFor(k).first, AssignStep.start);
      expect(stepsFor(k).last, AssignStep.review);
    }
  });
}
