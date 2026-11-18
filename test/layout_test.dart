import 'package:flutter_test/flutter_test.dart';
import 'package:folk_android_app/core/layout.dart';

void main() {
  test('window classes follow Material 3 breakpoints', () {
    expect(windowClassFor(360), WindowClass.compact);
    expect(windowClassFor(599.9), WindowClass.compact);
    expect(windowClassFor(600), WindowClass.medium);
    expect(windowClassFor(839.9), WindowClass.medium);
    expect(windowClassFor(840), WindowClass.expanded);
  });
}
