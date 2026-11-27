import 'package:flutter_test/flutter_test.dart';
import 'package:folk_android_app/features/admin/assign/assign_models.dart';

void main() {
  test('plan body carries the filters, the limit and the coordinators in the shape the server expects', () {
    final d = AssignDraft('EV1')
      ..kind = AssignKind.assign
      ..limit = 40;
    d.filters.add(FilterDraft('college', values: {'c1': 'CBIT'}));
    d.coords.add('9876543210');
    final b = d.planBody();
    expect(b['kind'], 'assign');
    expect(b['event'], 'EV1');
    expect(b['limit'], 40);
    expect((b['filters'] as List).last, {
      'field': 'college',
      'mode': 'only',
      'values': ['c1'],
    });
    expect(b['to'], {
      'coordinators': ['9876543210'],
      'keep_previous': false,
    });
  });

  test('"how many" only applies to a normal assignment', () {
    final d = AssignDraft('EV1')
      ..kind = AssignKind.followup
      ..limit = 40;
    expect(d.planBody()['limit'], 0);
  });

  test('everyone starts selected except women', () {
    final d = AssignDraft('EV1');
    expect(d.filters.single.field, 'gender');
    expect(d.filters.single.values.keys, ['M', '']);
  });

  test('filter summary is short when many values are ticked', () {
    final f = FilterDraft('branch', values: {'a': 'CSE', 'b': 'ECE'});
    expect(f.summary, 'Branch: CSE, ECE');
    final many = FilterDraft('branch', values: {for (var i = 0; i < 5; i++) '$i': 'B$i'});
    expect(many.summary, 'Branch: 5 selected');
  });

  test('reassigning unstarted calls has just one step', () {
    expect(stepsFor(AssignKind.move, reassign: true), [AssignStep.coordinators]);
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

  test('each kind is two steps: choose the contacts, then the coordinators', () {
    expect(stepsFor(null), [AssignStep.start]);
    for (final k in AssignKind.values) {
      expect(stepsFor(k).first, AssignStep.start);
      expect(stepsFor(k).last, AssignStep.coordinators);
      expect(stepsFor(k).length, 3);
    }
  });
}
