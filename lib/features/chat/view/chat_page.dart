import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:yap_chat/features/chats/data/data.dart';
import 'package:yap_chat/ui/ui.dart';

@RoutePage()
class ChatPage extends StatelessWidget {
  const ChatPage({
    super.key,
    required this.chat,
  });

  final Chat chat;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: PrimaryAppBar(
        title: chat.userName,
        // No action icon for now as per requirements for a simple stub
      ),
      body: Center(
        child: Text(
          'Диалог с ${chat.userName}',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}
