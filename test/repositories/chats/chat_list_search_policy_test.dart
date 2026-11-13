import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/repositories/chats/chats.dart';

void main() {
  late int micros;
  late ChatListSearchPolicy policy;
  setUp(() {
    micros = 0;
    policy = ChatListSearchPolicy(elapsedMicros: () => micros);
  });
  test('only a current complete head proves completeness for 30 seconds', () {
    expect(policy.hasCompleteCatalog, false);
    policy.confirmHead(policy.version, complete: true);
    expect(policy.hasCompleteCatalog, true);
    micros = 29999999;
    expect(policy.hasCompleteCatalog, true);
    micros++;
    expect(policy.hasCompleteCatalog, false);
    final ticket = policy.version;
    policy.invalidate();
    policy.confirmHead(ticket, complete: true);
    expect(policy.hasCompleteCatalog, false);
    policy.confirmHead(policy.version, complete: false);
    expect(policy.hasCompleteCatalog, false);
  });
  test('reuse requires matching committed revision and fresh evidence', () {
    policy.remember('alice', 'committed', policy.version);
    expect(policy.canReuse('alice', 'committed'), true);
    expect(policy.canReuse('alice', 'request-revision'), false);
    expect(policy.canReuse('alice', 'committed'), false);
    policy.remember('alice', 'new', policy.version);
    micros = 30000000;
    expect(policy.canReuse('alice', 'new'), false);
  });
  test('eight query LRU, invalidation and session reset stay bounded', () {
    for (var i = 0; i < 8; i++) {
      policy.remember('$i', '$i', policy.version);
    }
    expect(policy.canReuse('0', '0'), true);
    policy.remember('8', '8', policy.version);
    expect(policy.retainedQueries, 8);
    expect(policy.canReuse('1', '1'), false);
    expect(policy.canReuse('0', '0'), true);
    final old = policy.version;
    policy.reset();
    policy.remember('late', 'late', old);
    expect(policy.retainedQueries, 0);
    expect(policy.canReuse('0', '0'), false);
  });
  test('quota blocks for 60 seconds and retry cannot bypass it', () {
    policy.failed(StateError('429'), transport: false, quota: true);
    policy.allowProbe();
    policy.connected();
    expect(policy.canRequest, false);
    micros = 59999999;
    expect(policy.canRequest, false);
    micros++;
    expect(policy.canRequest, true);
  });
  test('transport failure needs recovery and invalidates cached evidence', () {
    policy.confirmHead(policy.version, complete: true);
    policy.remember('a', 'a', policy.version);
    policy.failed(StateError('network'), transport: true, quota: false);
    micros = 60000000;
    expect(policy.canRequest, false);
    expect(policy.hasCompleteCatalog, false);
    expect(policy.canReuse('a', 'a'), false);
    policy.confirmHead(policy.version, complete: false);
    expect(policy.canRequest, true);
  });
  test('error cooldown never shrinks a previous quota cooldown', () {
    policy.failed(StateError('quota'), transport: false, quota: true);
    micros = 1000000;
    policy.failed(StateError('other'), transport: false, quota: false);
    micros = 3000000;
    expect(policy.canRequest, false);
    micros = 60000000;
    expect(policy.canRequest, true);
  });
  test(
    'successful HTTP clears transport backoff immediately, and ordinary errors are not offline',
    () {
      policy.failed(StateError('network'), transport: true, quota: false);
      policy.connected();
      expect(policy.canRequest, true);
      policy.failed(StateError('bad format'), transport: false, quota: false);
      expect(policy.canRequest, false);
      micros = 2000000;
      expect(policy.canRequest, true);
    },
  );
  test('debounce is separate from minimum request spacing', () {
    expect(policy.delay(), const Duration(milliseconds: 350));
    policy.started();
    micros = 200000;
    expect(policy.delay(), const Duration(milliseconds: 800));
    expect(policy.delay(immediate: true), const Duration(milliseconds: 800));
    micros = 1000000;
    expect(policy.delay(immediate: true), Duration.zero);
    expect(policy.delay(), const Duration(milliseconds: 350));
  });
}
