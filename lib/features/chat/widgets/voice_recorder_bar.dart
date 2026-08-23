import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/chat/bloc/bloc.dart';
import 'package:yap_chat/features/chat/widgets/audio_waveform.dart';
import 'package:yap_chat/ui/widgets/glass_icon_button.dart';

class VoiceRecorderBar extends StatelessWidget {
  const VoiceRecorderBar({
    super.key,
    required this.state,
    required this.onDiscard,
    required this.onStop,
    required this.onTogglePreview,
    required this.onSeekUpdate,
    required this.onSeekEnd,
    required this.onSend,
  });

  final VoiceRecorderState state;
  final VoidCallback onDiscard;
  final VoidCallback onStop;
  final VoidCallback onTogglePreview;
  final ValueChanged<Duration> onSeekUpdate;
  final VoidCallback onSeekEnd;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final isRecording = state.status == VoiceRecorderStatus.recording;
    final duration = isRecording
        ? state.duration
        : state.recordedAudio!.duration;
    final visiblePosition = state.scrubPosition ?? state.playback.position;
    final displayedDuration = isRecording
        ? duration
        : _displayPlaybackDuration(visiblePosition, duration);
    final playbackDuration = state.playback.duration.inMilliseconds == 0
        ? duration
        : state.playback.duration;
    final progress = playbackDuration.inMilliseconds == 0
        ? 0.0
        : state.playback.isCompleted && state.scrubPosition == null
        ? 0.0
            : visiblePosition.inMilliseconds /
              playbackDuration.inMilliseconds;
    final foreground = context.colorScheme.onSurface;
    final canFinish = !isRecording || state.canFinishRecording;
    final systemPadding = MediaQuery.paddingOf(context);

    return SafeArea(
      top: false,
      left: false,
      right: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          systemPadding.left + 16,
          8,
          systemPadding.right + 16,
          8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
            GlassIconButton(
              icon: Icons.delete_outline_rounded,
              onTap: onDiscard,
              width: 50,
              height: 50,
              borderRadius: 20,
              iconSize: 28,
            ),
            const SizedBox(width: 8),
            Text(
              _formatDuration(displayedDuration),
              style: TextStyle(
                color: foreground,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AudioWaveform(
                values: state.amplitudes,
                activeColor: context.colorScheme.primary,
                inactiveColor: foreground.withValues(alpha: 0.25),
                progress: isRecording ? null : progress,
                fillFromRight: isRecording,
                showLatestSamples: isRecording,
                onSeekUpdate: isRecording
                    ? null
                    : (value) => onSeekUpdate(
                        Duration(
                          milliseconds: (duration.inMilliseconds * value).round(),
                        ),
                      ),
                onSeekEnd: isRecording ? null : onSeekEnd,
              ),
            ),
            const SizedBox(width: 8),
            Opacity(
              opacity: canFinish ? 1 : 0.45,
              child: IgnorePointer(
                ignoring: !canFinish,
                child: GlassIconButton(
                  icon: isRecording
                      ? Icons.stop_rounded
                      : state.playback.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  onTap: isRecording ? onStop : onTogglePreview,
                  width: 50,
                  height: 50,
                  borderRadius: 20,
                  iconSize: 28,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _SendVoiceButton(onTap: onSend, enabled: canFinish),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Duration _displayPlaybackDuration(
    Duration position,
    Duration totalDuration,
  ) {
    return position == Duration.zero ? totalDuration : position;
  }
}

class _SendVoiceButton extends StatelessWidget {
  const _SendVoiceButton({required this.onTap, required this.enabled});

  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: IgnorePointer(
        ignoring: !enabled,
        child: SizedBox(
          width: 50,
          height: 50,
          child: Material(
            color: context.colorScheme.primary,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Center(
                child: Icon(
                  Icons.send_rounded,
                  color: context.scaffoldBackgroundColor,
                  size: 28,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
