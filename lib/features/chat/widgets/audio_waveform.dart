import 'dart:math' as math;

import 'package:flutter/material.dart';

class AudioWaveform extends StatelessWidget {
  const AudioWaveform({
    super.key,
    required this.values,
    required this.activeColor,
    required this.inactiveColor,
    this.progress,
    this.barCount = 32,
    this.height = 30,
    this.fillFromRight = false,
    this.showLatestSamples = false,
    this.onSeekStart,
    this.onSeekUpdate,
    this.onSeekEnd,
  });

  final List<double> values;
  final Color activeColor;
  final Color inactiveColor;
  final double? progress;
  final int barCount;
  final double height;
  final bool fillFromRight;
  final bool showLatestSamples;
  final VoidCallback? onSeekStart;
  final ValueChanged<double>? onSeekUpdate;
  final VoidCallback? onSeekEnd;

  @override
  Widget build(BuildContext context) {
    final waveform = values;

    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = _buildLayout(constraints.maxWidth);
        final displayedValues = _buildValues(
          waveform,
          layout.barCount,
          alignToEnd: showLatestSamples,
          showLatestSamples: showLatestSamples,
        );
        final activeBars = progress == null
            ? math.min(waveform.length, layout.barCount)
            : (layout.barCount * progress!.clamp(0.0, 1.0)).round();

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapUp: onSeekUpdate == null || constraints.maxWidth <= 0
              ? null
              : (details) {
                  _reportSeek(
                    details.localPosition,
                    constraints.maxWidth,
                  );
                  onSeekEnd?.call();
                },
          onHorizontalDragStart: onSeekUpdate == null || constraints.maxWidth <= 0
              ? null
              : (_) => onSeekStart?.call(),
          onHorizontalDragUpdate: onSeekUpdate == null || constraints.maxWidth <= 0
              ? null
              : (details) => _reportSeek(
                  details.localPosition,
                  constraints.maxWidth,
                ),
          onHorizontalDragEnd: onSeekUpdate == null || constraints.maxWidth <= 0
              ? null
              : (_) => onSeekEnd?.call(),
          child: SizedBox(
            height: height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: List.generate(layout.barCount, (index) {
                final value = displayedValues[index].clamp(0.08, 1.0);
                final barHeight = math.max(4.0, height * value).toDouble();
                return Padding(
                  padding: EdgeInsets.only(
                    right: index == layout.barCount - 1
                        ? 0
                        : layout.spacing,
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    width: layout.barWidth,
                    height: barHeight,
                    decoration: BoxDecoration(
                      color: _isActive(index, layout.barCount, activeBars)
                          ? activeColor
                          : inactiveColor,
                      borderRadius: BorderRadius.circular(layout.barWidth),
                    ),
                  ),
                );
              }),
            ),
          ),
        );
      },
    );
  }

  _WaveformLayout _buildLayout(double maxWidth) {
    const spacing = 2.0;
    const minBarWidth = 2.0;
    final availableWidth = math.max(0.0, maxWidth);
    final maxBars = math.max(
      1,
      ((availableWidth + spacing) / (minBarWidth + spacing)).floor(),
    );
    final visibleCount = math.min(barCount, maxBars);
    final totalSpacing = (visibleCount - 1) * spacing;
    final barWidth = math.max(
      0.0,
      (availableWidth - totalSpacing) / visibleCount,
    );

    return _WaveformLayout(
      barCount: visibleCount,
      barWidth: barWidth,
      spacing: spacing,
    );
  }

  bool _isActive(int index, int barCount, int activeBars) {
    if (fillFromRight) return index >= barCount - activeBars;
    return index < activeBars;
  }

  List<double> _buildValues(
    List<double> source,
    int targetCount, {
    required bool alignToEnd,
    required bool showLatestSamples,
  }) {
    if (source.isEmpty) {
      return List<double>.generate(targetCount, _emptyValue);
    }

    if (source.length <= targetCount) {
      final paddingCount = targetCount - source.length;
      return List<double>.generate(
        targetCount,
        (index) {
          final sourceIndex = alignToEnd ? index - paddingCount : index;
          return sourceIndex >= 0 && sourceIndex < source.length
              ? source[sourceIndex]
              : _emptyValue(index);
        },
      );
    }

    if (showLatestSamples) {
      return source.sublist(source.length - targetCount);
    }

    final step = source.length / targetCount;
    return List<double>.generate(targetCount, (index) {
      final sourceIndex = math.min(source.length - 1, (index * step).floor());
      return source[sourceIndex];
    });
  }

  double _emptyValue(int index) => 0.22 + ((index * 11) % 17) / 34;

  void _reportSeek(Offset position, double width) {
    onSeekUpdate!((position.dx / width).clamp(0.0, 1.0).toDouble());
  }
}

class _WaveformLayout {
  const _WaveformLayout({
    required this.barCount,
    required this.barWidth,
    required this.spacing,
  });

  final int barCount;
  final double barWidth;
  final double spacing;
}
