import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/router/router.dart';

void main() {
  test('navigator observer factory returns fresh instances', () {
    final first = createAppNavigatorObservers();
    final second = createAppNavigatorObservers();

    expect(first, hasLength(second.length));
    for (var index = 0; index < first.length; index++) {
      expect(identical(first[index], second[index]), isFalse);
      expect(first[index].runtimeType, second[index].runtimeType);
    }
  });
}
