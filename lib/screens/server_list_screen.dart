// lib/screens/server_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/server_config.dart';
import '../models/server_group.dart';
import '../providers/providers.dart';
import 'server_edit_screen.dart';
import 'terminal_screen.dart';

class ServerListScreen extends ConsumerStatefulWidget {
  const ServerListScreen({super.key});

  @override
  ConsumerState<ServerListScreen> createState() => _ServerListScreenState();
}

class _ServerListScreenState extends ConsumerState<ServerListScreen> {
  /// Tracks which group IDs are currently expanded.
  final Set<int> _expandedGroups = {};

  // ---------------------------------------------------------------------------
  // Refresh helpers
  // ---------------------------------------------------------------------------

  void _invalidateProviders() {
    ref.invalidate(groupsProvider);
    ref.invalidate(serversProvider);
    ref.invalidate(groupedServersProvider);
  }

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  Future<void> _navigateToAddServer() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ServerEditScreen()),
    );
    if (result == true) _invalidateProviders();
  }

  Future<void> _navigateToEditServer(ServerConfig server) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ServerEditScreen(server: server)),
    );
    if (result == true) _invalidateProviders();
  }

  void _navigateToTerminal(ServerConfig server) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TerminalScreen(server: server)),
    );
  }

  // ---------------------------------------------------------------------------
  // Group operations
  // ---------------------------------------------------------------------------

  Future<void> _showAddGroupDialog() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建分组'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '分组名称',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (name != null && name.isNotEmpty) {
      final db = ref.read(databaseServiceProvider);
      await db.insertGroup(ServerGroup(name: name));
      _invalidateProviders();
    }
  }

  Future<void> _showRenameGroupDialog(ServerGroup group) async {
    final controller = TextEditingController(text: group.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名分组'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '分组名称',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (newName != null && newName.isNotEmpty && newName != group.name) {
      final db = ref.read(databaseServiceProvider);
      await db.updateGroup(group.copyWith(name: newName));
      _invalidateProviders();
    }
  }

  Future<void> _confirmDeleteGroup(ServerGroup group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除分组'),
        content: Text('确定要删除分组 "${group.name}" 吗？\n该分组下的服务器将变为未分组。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final db = ref.read(databaseServiceProvider);
      await db.deleteGroup(group.id!);
      _expandedGroups.remove(group.id!);
      _invalidateProviders();
    }
  }

  void _showGroupBottomSheet(ServerGroup group) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('重命名'),
              onTap: () {
                Navigator.pop(ctx);
                _showRenameGroupDialog(group);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('删除', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeleteGroup(group);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Server operations
  // ---------------------------------------------------------------------------

  Future<void> _confirmDeleteServer(ServerConfig server) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除服务器'),
        content: Text('确定要删除服务器 "${server.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final db = ref.read(databaseServiceProvider);
      final cred = ref.read(credentialServiceProvider);
      await db.deleteServer(server.id!);
      await cred.deleteCredentials(server.id!);
      _invalidateProviders();
    }
  }

  void _showServerBottomSheet(ServerConfig server) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('编辑'),
              onTap: () {
                Navigator.pop(ctx);
                _navigateToEditServer(server);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('删除', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeleteServer(server);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Widgets
  // ---------------------------------------------------------------------------

  Widget _buildServerTile(ServerConfig server) {
    return ListTile(
      leading: const Icon(Icons.computer),
      title: Text(server.name),
      subtitle: Text('${server.username}@${server.host}:${server.port}'),
      trailing: Icon(
        server.authType == AuthType.password ? Icons.password : Icons.key,
        size: 20,
      ),
      onTap: () => _navigateToTerminal(server),
      onLongPress: () => _showServerBottomSheet(server),
    );
  }

  Widget _buildGroupSection(
    ServerGroup group,
    List<ServerConfig> servers,
  ) {
    final isExpanded = _expandedGroups.contains(group.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: Icon(
            isExpanded ? Icons.folder_open : Icons.folder,
          ),
          title: Text(group.name),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${servers.length}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Icon(
                isExpanded ? Icons.expand_less : Icons.expand_more,
              ),
            ],
          ),
          onTap: () {
            setState(() {
              if (isExpanded) {
                _expandedGroups.remove(group.id);
              } else {
                _expandedGroups.add(group.id!);
              }
            });
          },
          onLongPress: () => _showGroupBottomSheet(group),
        ),
        if (isExpanded)
          ...servers.map(
            (server) => Padding(
              padding: const EdgeInsets.only(left: 16),
              child: _buildServerTile(server),
            ),
          ),
      ],
    );
  }

  Widget _buildUngroupedSection(List<ServerConfig> servers) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: const Icon(Icons.folder_off),
          title: const Text('未分组'),
          trailing: Text(
            '${servers.length}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        ...servers.map(
          (server) => Padding(
            padding: const EdgeInsets.only(left: 16),
            child: _buildServerTile(server),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Text(
        '点击 + 添加服务器',
        style: TextStyle(fontSize: 16),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(groupsProvider);
    final groupedServersAsync = ref.watch(groupedServersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('TomSSH'),
        actions: [
          IconButton(
            icon: const Icon(Icons.create_new_folder),
            tooltip: '新建分组',
            onPressed: _showAddGroupDialog,
          ),
        ],
      ),
      body: groupsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
        data: (groups) => groupedServersAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('加载失败: $e')),
          data: (groupedServers) {
            // Check if there are any servers at all.
            final totalServers = groupedServers.values
                .fold<int>(0, (sum, list) => sum + list.length);

            if (totalServers == 0 && groups.isEmpty) {
              return _buildEmptyState();
            }

            final ungrouped = groupedServers[null] ?? [];

            return ListView(
              children: [
                // Groups with their servers
                for (final group in groups)
                  _buildGroupSection(
                    group,
                    groupedServers[group.id] ?? [],
                  ),
                // Ungrouped servers at the bottom
                if (ungrouped.isNotEmpty) _buildUngroupedSection(ungrouped),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToAddServer,
        tooltip: '添加服务器',
        child: const Icon(Icons.add),
      ),
    );
  }
}
