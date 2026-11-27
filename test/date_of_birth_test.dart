import 'package:flutter_test/flutter_test.dart';
import 'package:folk_android_app/features/register/person_form.dart';

void main() {
  test('age counts a birthday only once it has come this year', () {
    expect(ageFrom('2005-11-25', DateTime(2026, 11, 25)), 21);
    expect(ageFrom('2005-11-26', DateTime(2026, 11, 25)), 20);
    expect(ageFrom('2004-02-29', DateTime(2026, 3, 1)), 22);
    expect(ageFrom('', DateTime(2026, 1, 1)), 0);
  });
}
