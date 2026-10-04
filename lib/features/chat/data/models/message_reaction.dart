import 'package:equatable/equatable.dart';

/// The wire protocol uses codes; rendering always uses bundled artwork.
enum ReactionCode {
  heart,
  like,
  cry,
  fire,
  mindBlown,
  poop;

  String get wireName => this == mindBlown ? 'mind_blown' : name;
  String get assetPath => 'assets/reactions/$wireName.svg';
  static ReactionCode? parse(Object? value) {
    for (final code in values) {
      if (code.wireName == value) return code;
    }
    return null;
  }
}

class MessageReaction extends Equatable {
  const MessageReaction({required this.userId, required this.code});
  final String userId;
  final ReactionCode code;
  Map<String, dynamic> toJson() => {'user_id': userId, 'code': code.wireName};
  @override
  List<Object?> get props => [userId, code];
}

class MessageReactionState extends Equatable {
  const MessageReactionState({
    this.version = 0,
    this.reactions = const [],
    this.userRevisions = const {},
  });
  factory MessageReactionState.fromJson(Object? source) {
    if (source is! Map) return const MessageReactionState();
    final entries = <MessageReaction>[];
    for (final value in source['reactions'] as List? ?? const []) {
      if (value is! Map || value['user_id'] is! String) continue;
      final code = ReactionCode.parse(value['code']);
      if (code != null) {
        entries.add(
          MessageReaction(userId: value['user_id'] as String, code: code),
        );
      }
    }
    return MessageReactionState(
      version: (source['version'] as num?)?.toInt() ?? 0,
      reactions: List.unmodifiable(entries),
      userRevisions: Map.unmodifiable({
        for (final entry
            in (source['user_revisions'] as Map? ?? const {}).entries)
          if (entry.key is String && entry.value is num)
            entry.key as String: (entry.value as num).toInt(),
      }),
    );
  }
  final int version;
  final List<MessageReaction> reactions;
  final Map<String, int> userRevisions;
  ReactionCode? codeFor(String userId) =>
      reactions.where((r) => r.userId == userId).firstOrNull?.code;
  MessageReactionState withChoice(String userId, ReactionCode? code) =>
      MessageReactionState(
        version: version,
        userRevisions: userRevisions,
        reactions: List.unmodifiable([
          ...reactions.where((r) => r.userId != userId),
          if (code != null) MessageReaction(userId: userId, code: code),
        ]),
      );
  Map<String, dynamic> toJson() => {
    'version': version,
    'reactions': reactions.map((r) => r.toJson()).toList(),
    'user_revisions': userRevisions,
  };
  @override
  List<Object?> get props => [version, reactions, userRevisions];
}

class MessageReactionChange {
  const MessageReactionChange(this.chatId, this.messageId, this.state);
  final String chatId;
  final String messageId;
  final MessageReactionState state;
}
