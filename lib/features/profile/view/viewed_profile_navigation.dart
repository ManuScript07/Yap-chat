import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:yap_chat/router/router.gr.dart';

Future<void> openViewedProfile(
  BuildContext context, {
  required String userId,
  String? originChatId,
  bool waitForClose = false,
}) async {
  final authRouter = context.router.root.innerRouterOf<StackRouter>(
    AuthGateRoute.name,
  );
  if (authRouter == null) return;
  final navigation = authRouter.push(
    ViewedProfileRoute(userId: userId, originChatId: originChatId),
  );
  if (waitForClose) {
    await navigation;
  } else {
    unawaited(navigation);
  }
}
