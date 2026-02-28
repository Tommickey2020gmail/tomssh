// lib/screens/server_list_screen.dart
// Placeholder – will be fully implemented in Task 7.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ServerListScreen extends ConsumerWidget {
  const ServerListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('TomSSH')),
      body: const Center(child: Text('服务器列表 (待实现)')),
    );
  }
}
