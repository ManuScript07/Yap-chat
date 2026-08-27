import 'dart:async';

import 'package:flutter/widgets.dart';

Future<double?> resolveImageAspectRatio(
  BuildContext context,
  ImageProvider<Object> provider, {
  Duration timeout = const Duration(milliseconds: 400),
}) async {
  final stream = provider.resolve(createLocalImageConfiguration(context));
  final completer = Completer<double?>();
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (image, _) {
      if (!completer.isCompleted) {
        completer.complete(image.image.width / image.image.height);
      }
      stream.removeListener(listener);
    },
    onError: (_, _) {
      if (!completer.isCompleted) completer.complete(null);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);

  return completer.future.timeout(
    timeout,
    onTimeout: () {
      stream.removeListener(listener);
      return null;
    },
  );
}
