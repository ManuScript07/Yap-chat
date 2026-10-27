/// Some image batches are already in the durable outbox. Retrying the complete
/// original selection would duplicate them, so the owner retains only the rest.
class PartialImageSendException implements Exception {
  PartialImageSendException({
    required Iterable<String> queuedPaths,
    required Iterable<String> remainingPaths,
    required this.cause,
  }) : queuedPaths = List.unmodifiable(queuedPaths),
       remainingPaths = List.unmodifiable(remainingPaths);

  final List<String> queuedPaths;
  final List<String> remainingPaths;
  final Object cause;

  @override
  String toString() => 'PartialImageSendException';
}
