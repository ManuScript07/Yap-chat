import 'package:flutter_test/flutter_test.dart';
import 'package:yap_chat/features/chat/data/models/message_reaction.dart';
import 'package:yap_chat/features/chat/widgets/message_reactions.dart';

void main() {
  test('replacement retains position; removal and re-add join the end', () {
    var state = const MessageReactionState(
      version: 2,
      reactions: [
        MessageReaction(userId: 'z', code: ReactionCode.heart, position: 1),
        MessageReaction(userId: 'a', code: ReactionCode.heart, position: 2),
      ],
    );
    state = state.withChoice('z', ReactionCode.fire);
    expect(state.reactions.first.userId, 'z');
    expect(state.reactions.first.position, 1);
    expect(
      MessageReactions.groupsFor(state).first.first.code,
      ReactionCode.fire,
    );
    state = state.withChoice('z', null).withChoice('z', ReactionCode.heart);
    expect(state.reactions.last.position, 3);
    expect(MessageReactions.groupsFor(state).single.map((r) => r.userId), [
      'a',
      'z',
    ]);
    expect(MessageReactionState.fromJson(state.toJson()), state);
  });
  test(
    'server order wins over uuid and input order, old cache stays readable',
    () {
      final state = MessageReactionState.fromJson({
        'version': 7,
        'reactions': [
          {'user_id': 'a', 'code': 'heart', 'position': 7},
          {'user_id': 'z', 'code': 'heart', 'position': 1},
        ],
      });
      expect(MessageReactions.groupsFor(state).single.map((r) => r.userId), [
        'z',
        'a',
      ]);
      final old = MessageReactionState.fromJson({
        'reactions': [
          {'user_id': 'z', 'code': 'heart'},
          {'user_id': 'a', 'code': 'heart'},
        ],
      });
      expect(
        old.withChoice('z', ReactionCode.like).reactions.first.userId,
        'z',
      );
    },
  );
}
