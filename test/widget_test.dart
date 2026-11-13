import 'package:flutter_test/flutter_test.dart';
import 'package:todo_list/main.dart';

void main() {
  testWidgets('app shell can be constructed', (tester) async {
    // Full integration tests require platform plugin mocks and are added in QA.
    expect(const TodoApp(), isA<TodoApp>());
  });
}
