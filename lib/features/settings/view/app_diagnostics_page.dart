import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yap_chat/app/app_config.dart';
import 'package:yap_chat/core/services/app_diagnostics.dart';

/// Developer-only page. It is reachable only from a debug build that was
/// explicitly started with ENABLE_DIAGNOSTICS=true.
class AppDiagnosticsPage extends StatefulWidget {
  const AppDiagnosticsPage({super.key});

  @override
  State<AppDiagnosticsPage> createState() => _AppDiagnosticsPageState();
}

class _AppDiagnosticsPageState extends State<AppDiagnosticsPage> {
  AppDiagnosticsSnapshot? _snapshot;
  var _isLoading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final config = context.read<AppConfig>();
      final diagnostics = context.read<AppDiagnostics>();
      await diagnostics.refreshCacheSnapshot(
        config.database,
        ownerUserId: config.accountSessionController.userId,
      );
      if (mounted) setState(() => _snapshot = diagnostics.snapshot());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _copy() async {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    await Clipboard.setData(
      ClipboardData(
        text: const JsonEncoder.withIndent('  ').convert(snapshot.toJson()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final json = _snapshot == null
        ? 'Collecting diagnostics…'
        : const JsonEncoder.withIndent('  ').convert(_snapshot!.toJson());
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Copy JSON',
            onPressed: _snapshot == null ? null : _copy,
            icon: const Icon(Icons.copy_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 112, 16, 24),
          child: SelectableText(
            json,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ),
      ),
    );
  }
}
