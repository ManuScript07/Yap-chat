import 'package:flutter/material.dart';
import 'package:yap_chat/features/chat/bloc/voice_recorder_cubit.dart';

/// System Back dismisses the keyboard first; an explicit header exit can bypass
/// only that step after safely finishing the recording.
class ChatPopScope extends StatelessWidget {
  const ChatPopScope({
    super.key,
    required this.child,
    required this.voiceState,
    required this.allowPop,
    required this.onExit,
  });

  final Widget child;
  final VoiceRecorderState voiceState;
  final bool allowPop;
  final Future<void> Function() onExit;

  @override
  Widget build(BuildContext context) {
    final isKeyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return PopScope(
      canPop:
          allowPop ||
          (!isKeyboardOpen &&
              (!voiceState.hasPendingRecording ||
                  voiceState.status == VoiceRecorderStatus.preview)),
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (isKeyboardOpen && !allowPop) {
          FocusManager.instance.primaryFocus?.unfocus();
          return;
        }
        if (voiceState.hasPendingRecording) await onExit();
      },
      child: child,
    );
  }
}
