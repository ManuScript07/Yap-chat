import 'package:drift/drift.dart';
import 'package:yap_chat/features/chat/data/data.dart';

/// Exact, stable keyset boundary. It remains valid if its message is deleted.
class ChatHistoryCursor implements Comparable<ChatHistoryCursor> {
  const ChatHistoryCursor(this.micros, this.id);

  factory ChatHistoryCursor.of(ChatMessage message) =>
      ChatHistoryCursor(message.timestamp.microsecondsSinceEpoch, message.id);

  final int micros;
  final String id;
  DateTime get timestamp =>
      DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true);

  @override
  int compareTo(ChatHistoryCursor other) {
    final time = micros.compareTo(other.micros);
    return time == 0 ? id.compareTo(other.id) : time;
  }

  Expression<bool> before(Expression<int> time, Expression<String> messageId) =>
      _CursorComparison(time, messageId, this, '<');

  Expression<bool> after(Expression<int> time, Expression<String> messageId) =>
      _CursorComparison(time, messageId, this, '>');
}

/// SQLite row-value comparison can seek the composite index even when many
/// messages share one timestamp. Values are bound parameters, never SQL text.
class _CursorComparison extends Expression<bool> {
  _CursorComparison(this.time, this.messageId, this.cursor, this.operator);
  final Expression<int> time;
  final Expression<String> messageId;
  final ChatHistoryCursor cursor;
  final String operator;

  @override
  Precedence get precedence => Precedence.primary;

  @override
  void writeInto(GenerationContext context) {
    context.buffer.write('((');
    time.writeInto(context);
    context.buffer.write(', ');
    messageId.writeInto(context);
    context.buffer.write(') $operator (');
    Variable<int>(cursor.micros).writeInto(context);
    context.buffer.write(', ');
    Variable<String>(cursor.id).writeInto(context);
    context.buffer.write('))');
  }
}
