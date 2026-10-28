import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/core/core.dart';

/// Reads the shared snapshot without rebuilding the surrounding screen.
/// Standalone consumers retain their ordinary UI when no provider is installed.
class ConnectionStatusBuilder extends StatelessWidget {
  const ConnectionStatusBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, bool connecting) builder;

  @override
  Widget build(BuildContext context) {
    final status = context.read<AppConnectionStatus?>();
    if (status == null) return builder(context, false);

    return ValueListenableBuilder<bool>(
      valueListenable: status.listenable,
      builder: (context, connecting, _) => builder(context, connecting),
    );
  }
}
