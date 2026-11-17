import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:yap_chat/core/core.dart';

Future<T?> showProfileActionSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: false,
  backgroundColor: context.scaffoldBackgroundColor,
  barrierColor: context.colorScheme.primary.withValues(alpha: .22),
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
  ),
  clipBehavior: Clip.antiAlias,
  showDragHandle: true,
  builder: (context) {
    final size = MediaQuery.sizeOf(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: math.min(size.width, 720),
        maxHeight: size.height * .72,
      ),
      child: SingleChildScrollView(child: Builder(builder: builder)),
    );
  },
);

class ProfileActionSheetContent extends StatelessWidget {
  const ProfileActionSheetContent({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        listTileTheme: theme.listTileTheme.copyWith(
          titleTextStyle: TextStyle(
            color: context.colorScheme.onSurface,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            height: 1.2,
            letterSpacing: .5,
          ),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          12,
          0,
          12,
          MediaQuery.paddingOf(context).bottom + 12,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}
