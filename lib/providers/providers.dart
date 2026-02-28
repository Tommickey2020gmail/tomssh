// lib/providers/providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/database_service.dart';
import '../services/credential_service.dart';
import '../models/server_group.dart';
import '../models/server_config.dart';

// Service singletons
final databaseServiceProvider = Provider((ref) => DatabaseService());
final credentialServiceProvider = Provider((ref) => CredentialService());

// Auth state – uses Notifier (non-legacy) instead of StateProvider
class IsUnlockedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void unlock() => state = true;
  void lock() => state = false;
}

final isUnlockedProvider =
    NotifierProvider<IsUnlockedNotifier, bool>(IsUnlockedNotifier.new);

// Server groups
final groupsProvider = FutureProvider<List<ServerGroup>>((ref) async {
  final db = ref.watch(databaseServiceProvider);
  return db.getGroups();
});

// All servers
final serversProvider = FutureProvider<List<ServerConfig>>((ref) async {
  final db = ref.watch(databaseServiceProvider);
  return db.getServers();
});

// Grouped servers: Map<int?, List<ServerConfig>> where null key = ungrouped
final groupedServersProvider =
    FutureProvider<Map<int?, List<ServerConfig>>>((ref) async {
  final servers = await ref.watch(serversProvider.future);
  final map = <int?, List<ServerConfig>>{};
  for (final s in servers) {
    map.putIfAbsent(s.groupId, () => []).add(s);
  }
  return map;
});
