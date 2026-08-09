sealed class ChatsEvent {
  const ChatsEvent();
}

final class ChatsLoadStarted extends ChatsEvent {
  const ChatsLoadStarted();
}

final class ChatsSearchChanged extends ChatsEvent {
  const ChatsSearchChanged(this.query);

  final String query;
}

final class ChatSelectionToggled extends ChatsEvent {
  const ChatSelectionToggled(this.id);

  final String id;
}

final class ChatSelectionCleared extends ChatsEvent {
  const ChatSelectionCleared();
}

final class ChatsDeleted extends ChatsEvent {
  const ChatsDeleted();
}

final class ChatsMarkedAsRead extends ChatsEvent {
  const ChatsMarkedAsRead();
}

final class ChatsMuteToggled extends ChatsEvent {
  const ChatsMuteToggled();
}
