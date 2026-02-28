import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/lock_screen.dart';

void main() {
  runApp(const ProviderScope(child: TomSSHApp()));
}

class TomSSHApp extends StatelessWidget {
  const TomSSHApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TomSSH',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const LockScreen(),
    );
  }
}
