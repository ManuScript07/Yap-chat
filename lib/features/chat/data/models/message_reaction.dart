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
  const MessageReaction({
    required this.userId,
    required this.code,
    this.position = 0,
  });
  final String userId;
  final ReactionCode code;

  /// Server-assigned order of the current uninterrupted reaction. Replacing
  /// its emoji keeps this position; removing and adding gets a new position.
  final int position;
  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'code': code.wireName,
    'position': position,
  };
  @override
  List<Object?> get props => [userId, code, position];
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
          MessageReaction(
            userId: value['user_id'] as String,
            code: code,
            position: (value['position'] as num?)?.toInt() ?? 0,
          ),
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
  MessageReactionState withChoice(String userId, ReactionCode? code) {
    final previous = reactions.where((r) => r.userId == userId).firstOrNull;
    final position =
        previous?.position ??
        reactions.fold(
              version,
              (latest, r) => r.position > latest ? r.position : latest,
            ) +
            1;
    final choices = <MessageReaction>[
      for (final reaction in reactions)
        if (reaction.userId != userId)
          reaction
        else if (code != null)
          MessageReaction(userId: userId, code: code, position: position),
      if (previous == null && code != null)
        MessageReaction(userId: userId, code: code, position: position),
    ];
    return MessageReactionState(
      version: version,
      userRevisions: userRevisions,
      reactions: List.unmodifiable(choices),
    );
  }

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
