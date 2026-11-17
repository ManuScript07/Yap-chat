import 'dart:async';

import 'package:flutter/widgets.dart';

class SwipeTabController extends PageController {
  SwipeTabController({super.initialPage}) : super(keepPage: false);

  double get progress => positions.length == 1
      ? page ?? initialPage.toDouble()
      : initialPage.toDouble();

  void select(int index) {
    if (positions.length != 1 || progress == index) return;
    if ((progress - index).abs() > 1) {
      jumpToPage(index);
    } else {
      unawaited(
        animateToPage(
          index,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }
}

/// Reports the settled page, so a partial swipe never activates its neighbor.
class SwipeTabView extends StatelessWidget {
  const SwipeTabView({
    super.key,
    required this.controller,
    required this.onSettled,
    required this.children,
  });

  final SwipeTabController controller;
  final ValueChanged<int> onSettled;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollEndNotification>(
        onNotification: (notification) {
          if (notification.depth == 0 &&
              notification.metrics.axis == Axis.horizontal) {
            scheduleMicrotask(() {
              if (!context.mounted ||
                  controller.positions.length != 1 ||
                  controller.position.isScrollingNotifier.value) {
                return;
              }
              onSettled(controller.progress.round());
            });
          }
          return false;
        },
        child: PageView(controller: controller, children: children),
      );
}
