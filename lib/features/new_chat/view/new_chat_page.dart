import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:yap_chat/ui/ui.dart';

@RoutePage()
class NewChatPage extends StatelessWidget {
  const NewChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const PrimaryAppBar(
        title: 'Новый чат',
      ),
      body: const Center(
        child: Text('Выберите собеседника'),
      ),
    );
  }
}
