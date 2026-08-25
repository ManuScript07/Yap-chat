import 'package:flutter/material.dart';

class KeyboardDismissPopScope extends StatelessWidget {
  const KeyboardDismissPopScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isKeyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return PopScope(
      canPop: !isKeyboardOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && isKeyboardOpen) {
          FocusManager.instance.primaryFocus?.unfocus();
          FocusScope.of(context).unfocus();
        }
      },
      child: child,
    );
  }
}
