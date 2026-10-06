import 'package:flutter/widgets.dart';

/// Owns composer focus separately from the platform keyboard's visibility.
/// Android Back can hide the IME while leaving this node focused.
class ChatComposerFocusController {
  final FocusNode focusNode = FocusNode(debugLabel: 'chat-composer');
  int _generation = 0;
  bool _disposed = false;

  void dismiss() {
    if (_disposed) return;
    _generation++;
    focusNode.unfocus();
  }

  Future<T> suspendForMenu<T>(
    BuildContext context,
    Future<T> Function() openMenu,
  ) async {
    final restoreKeyboard =
        focusNode.hasFocus && View.of(context).viewInsets.bottom > 0;
    final route = ModalRoute.of(context);
    dismiss();
    final generation = _generation;
    try {
      return await openMenu();
    } finally {
      if (restoreKeyboard && !_disposed && context.mounted) {
        // Let the popped route relinquish focus before restoring the composer.
        await WidgetsBinding.instance.endOfFrame;
        if (!_disposed &&
            generation == _generation &&
            context.mounted &&
            route?.isCurrent == true &&
            focusNode.context != null &&
            focusNode.canRequestFocus) {
          focusNode.requestFocus();
        }
      }
    }
  }

  void dispose() {
    _disposed = true;
    _generation++;
    focusNode.dispose();
  }
}
