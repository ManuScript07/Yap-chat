import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/chat/bloc/bloc.dart';
import 'package:yap_chat/features/chat/data/data.dart';
import 'package:yap_chat/features/chat/widgets/message_status_icon.dart';
import 'package:yap_chat/features/chat/widgets/audio_waveform.dart';
import 'package:yap_chat/repositories/repositories.dart';

class AudioMessageContent extends StatelessWidget {
  const AudioMessageContent({super.key, required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => AudioMessagePlayerCubit(
        playerRepository: context.read<IAudioPlayerRepository>(),
      ),
      child: _AudioMessageView(message: message),
    );
  }
}

class _AudioMessageView extends StatelessWidget {
  const _AudioMessageView({required this.message});

  static final _timeFormat = DateFormat('HH:mm');

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final audioUrl = message.audioUrl;
    if (audioUrl == null || audioUrl.isEmpty) return const SizedBox.shrink();

    final isMine = message.isMine;
    final foreground = isMine
        ? context.scaffoldBackgroundColor
        : context.colorScheme.onSecondaryContainer;
    final waveformInactive = foreground.withValues(alpha: 0.25);

    return BlocBuilder<AudioMessagePlayerCubit, AudioMessagePlayerState>(
      builder: (context, state) {
        final messageDuration = message.audioDuration ?? Duration.zero;
        final visiblePosition = state.scrubPosition ?? state.playback.position;
        final effectiveDuration = state.playback.duration == Duration.zero
            ? messageDuration
            : state.playback.duration;
        final progress = effectiveDuration.inMilliseconds == 0
            ? 0.0
            : state.playback.isCompleted && state.scrubPosition == null
            ? 0.0
            : visiblePosition.inMilliseconds /
                  effectiveDuration.inMilliseconds;
        final displayedDuration =
                (state.playback.isCompleted && state.scrubPosition == null) ||
                    visiblePosition == Duration.zero
            ? messageDuration
            : visiblePosition;

        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                _AudioActionButton(
                  isLoading:
                      state.isLoading || message.status == MessageStatus.sending,
                  isPlaying: state.playback.isPlaying,
                  foreground: foreground,
                  onTap: () {
                    context.read<AudioMessagePlayerCubit>().toggle(audioUrl);
                  },
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 130),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AudioWaveform(
                          values: message.audioWaveform,
                          activeColor: foreground,
                          inactiveColor: waveformInactive,
                          progress: progress,
                          height: 26,
                          onSeekUpdate: message.status == MessageStatus.sending
                              ? null
                              : (value) {
                                  final position = Duration(
                                    milliseconds:
                                        (effectiveDuration.inMilliseconds * value)
                                            .round(),
                                  );
                                  context
                                      .read<AudioMessagePlayerCubit>()
                                      .previewSeek(position);
                                },
                          onSeekEnd: message.status == MessageStatus.sending
                              ? null
                              : () => context
                                  .read<AudioMessagePlayerCubit>()
                                  .finishSeeking(audioUrl),
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Text(
                              _formatDuration(displayedDuration),
                              style: TextStyle(
                                color: foreground.withValues(alpha: 0.78),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              _timeFormat.format(message.timestamp),
                              style: TextStyle(
                                color: foreground.withValues(alpha: 0.78),
                                fontSize: 13,
                              ),
                            ),
                            if (isMine) ...[
                              const SizedBox(width: 4),
                              _StatusIcon(
                                status: message.status,
                                color: foreground,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _AudioActionButton extends StatelessWidget {
  const _AudioActionButton({
    required this.isLoading,
    required this.isPlaying,
    required this.foreground,
    required this.onTap,
  });

  final bool isLoading;
  final bool isPlaying;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 42,
      child: Material(
        color: foreground.withValues(alpha: 0.15),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: isLoading ? null : onTap,
          child: Center(
            child: isLoading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: foreground,
                    ),
                  )
                : Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: foreground,
                    size: 28,
                  ),
          ),
        ),
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status, required this.color});

  final MessageStatus status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return MessageStatusIcon(status: status, color: color, size: 17);
  }
}
