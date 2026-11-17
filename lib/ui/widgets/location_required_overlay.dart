import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';

class LocationRequiredBackdrop extends StatelessWidget {
  const LocationRequiredBackdrop({super.key});

  @override
  Widget build(BuildContext context) => BackdropFilter(
    filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
    child: ColoredBox(
      color: context.scaffoldBackgroundColor.withValues(alpha: .42),
    ),
  );
}

class LocationRequiredOverlay extends StatelessWidget {
  const LocationRequiredOverlay({
    super.key,
    required this.bottomInset,
    required this.onRetry,
    this.hidden = false,
    this.busy = false,
  });

  final double bottomInset;
  final VoidCallback? onRetry;
  final bool hidden;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    if (!isLandscape) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, bottomInset),
          child: _LocationRequiredPanel(
            onRetry: busy ? null : onRetry,
            hidden: hidden,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final panelWidth = math.min(constraints.maxWidth, 420.0);
          final scrollExtent = math.max(bottomInset - 50, 0.0);
          return SingleChildScrollView(
            reverse: true,
            physics: const ClampingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight + scrollExtent,
              ),
              child: Align(
                alignment: Alignment.center,
                child: SizedBox(
                  width: panelWidth,
                  child: _LocationRequiredPanel(
                    onRetry: busy ? null : onRetry,
                    hidden: hidden,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LocationRequiredPanel extends StatelessWidget {
  const _LocationRequiredPanel({required this.onRetry, this.hidden = false});

  final VoidCallback? onRetry;
  final bool hidden;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(28),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            hidden
                ? context.l10n.nearbyHiddenTitle
                : context.l10n.nearbyLocationRequiredTitle,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            hidden
                ? context.l10n.nearbyHiddenContent
                : context.l10n.nearbyLocationRequiredContent,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Center(
            child: SizedBox(
              width: 230,
              height: 58,
              child: FilledButton(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  backgroundColor: context.colorScheme.primary,
                  foregroundColor: context.colorScheme.onSurface,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  hidden
                      ? context.l10n.nearbyEnableVisibility
                      : context.l10n.nearbyLocationUpdateShort,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
