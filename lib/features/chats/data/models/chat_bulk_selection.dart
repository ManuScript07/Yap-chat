/// Shared client contract for the server's atomic chat-action batch.
abstract final class ChatBulkSelection {
  static const maximum = 50;

  static void validate(Set<String> ids) {
    if (ids.length > maximum) {
      throw ArgumentError.value(ids.length, 'ids', 'Maximum batch is $maximum');
    }
  }
}
