# TomSSH Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build an Android SSH terminal app with server grouping, multi-tab sessions, dual auth, and encrypted credential storage.

**Architecture:** Flutter single-codebase app using provider pattern (Riverpod) for state management. SQLite stores server/group configs, flutter_secure_storage handles encrypted credentials. dartssh2 provides SSH connections piped into xterm terminal widgets. Multi-tab via custom TabController.

**Tech Stack:** Flutter 3.38.5, dartssh2 2.13.0, xterm 4.0.0, flutter_secure_storage 10.0.0, sqflite 2.4.2, encrypt 5.0.3, flutter_riverpod 3.2.1

**Flutter binary:** `/home/tommy/flutter_3.38.5_stable/bin/flutter`

---

### Task 1: Create Flutter Project and Add Dependencies

**Files:**
- Create: `pubspec.yaml` (via flutter create)
- Modify: `pubspec.yaml` (add dependencies)
- Modify: `android/app/build.gradle.kts` (set minSdk 23)

**Step 1: Create Flutter project**

```bash
cd /home/tommy/code/flutter/tomssh
/home/tommy/flutter_3.38.5_stable/bin/flutter create --org com.tom --project-name tomssh .
```

**Step 2: Add dependencies to pubspec.yaml**

Add under `dependencies:`:
```yaml
dependencies:
  flutter:
    sdk: flutter
  dartssh2: ^2.13.0
  xterm: ^4.0.0
  flutter_secure_storage: ^10.0.0
  sqflite: ^2.4.2
  path: ^1.9.0
  encrypt: ^5.0.3
  flutter_riverpod: ^3.2.1
  crypto: ^3.0.6
```

**Step 3: Set Android minSdk to 23**

In `android/app/build.gradle.kts`, change `minSdk` to `23`.

**Step 4: Run flutter pub get**

```bash
/home/tommy/flutter_3.38.5_stable/bin/flutter pub get
```
Expected: No errors.

**Step 5: Verify project builds**

```bash
/home/tommy/flutter_3.38.5_stable/bin/flutter build apk --debug
```
Expected: BUILD SUCCESSFUL

**Step 6: Init git and commit**

```bash
cd /home/tommy/code/flutter/tomssh
git init
git add -A
git commit -m "feat: init Flutter project with SSH dependencies"
```

---

### Task 2: Data Models and Database Service

**Files:**
- Create: `lib/models/server_group.dart`
- Create: `lib/models/server_config.dart`
- Create: `lib/services/database_service.dart`

**Step 1: Create ServerGroup model**

```dart
// lib/models/server_group.dart
class ServerGroup {
  final int? id;
  final String name;
  final int sortOrder;

  ServerGroup({this.id, required this.name, this.sortOrder = 0});

  Map<String, dynamic> toMap() => {
    'id': id, 'name': name, 'sort_order': sortOrder,
  };

  factory ServerGroup.fromMap(Map<String, dynamic> map) => ServerGroup(
    id: map['id'] as int?,
    name: map['name'] as String,
    sortOrder: map['sort_order'] as int? ?? 0,
  );

  ServerGroup copyWith({int? id, String? name, int? sortOrder}) => ServerGroup(
    id: id ?? this.id,
    name: name ?? this.name,
    sortOrder: sortOrder ?? this.sortOrder,
  );
}
```

**Step 2: Create ServerConfig model**

```dart
// lib/models/server_config.dart
enum AuthType { password, key }

class ServerConfig {
  final int? id;
  final String name;
  final String host;
  final int port;
  final String username;
  final AuthType authType;
  final int? groupId;
  final int sortOrder;

  ServerConfig({
    this.id,
    required this.name,
    required this.host,
    this.port = 22,
    required this.username,
    required this.authType,
    this.groupId,
    this.sortOrder = 0,
  });

  Map<String, dynamic> toMap() => {
    'id': id, 'name': name, 'host': host, 'port': port,
    'username': username, 'auth_type': authType.name,
    'group_id': groupId, 'sort_order': sortOrder,
  };

  factory ServerConfig.fromMap(Map<String, dynamic> map) => ServerConfig(
    id: map['id'] as int?,
    name: map['name'] as String,
    host: map['host'] as String,
    port: map['port'] as int? ?? 22,
    username: map['username'] as String,
    authType: AuthType.values.byName(map['auth_type'] as String),
    groupId: map['group_id'] as int?,
    sortOrder: map['sort_order'] as int? ?? 0,
  );

  ServerConfig copyWith({
    int? id, String? name, String? host, int? port,
    String? username, AuthType? authType, int? groupId, int? sortOrder,
  }) => ServerConfig(
    id: id ?? this.id, name: name ?? this.name,
    host: host ?? this.host, port: port ?? this.port,
    username: username ?? this.username,
    authType: authType ?? this.authType,
    groupId: groupId ?? this.groupId,
    sortOrder: sortOrder ?? this.sortOrder,
  );
}
```

**Step 3: Create DatabaseService**

```dart
// lib/services/database_service.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/server_group.dart';
import '../models/server_config.dart';

class DatabaseService {
  static Database? _database;

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'tomssh.db');
    return openDatabase(path, version: 1, onCreate: _onCreate);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE groups (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        sort_order INTEGER DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE servers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        host TEXT NOT NULL,
        port INTEGER DEFAULT 22,
        username TEXT NOT NULL,
        auth_type TEXT NOT NULL,
        group_id INTEGER,
        sort_order INTEGER DEFAULT 0,
        FOREIGN KEY (group_id) REFERENCES groups(id) ON DELETE SET NULL
      )
    ''');
  }

  // --- Groups ---
  Future<List<ServerGroup>> getGroups() async {
    final db = await database;
    final maps = await db.query('groups', orderBy: 'sort_order');
    return maps.map((m) => ServerGroup.fromMap(m)).toList();
  }

  Future<int> insertGroup(ServerGroup group) async {
    final db = await database;
    return db.insert('groups', group.toMap()..remove('id'));
  }

  Future<void> updateGroup(ServerGroup group) async {
    final db = await database;
    await db.update('groups', group.toMap(), where: 'id = ?', whereArgs: [group.id]);
  }

  Future<void> deleteGroup(int id) async {
    final db = await database;
    await db.delete('groups', where: 'id = ?', whereArgs: [id]);
  }

  // --- Servers ---
  Future<List<ServerConfig>> getServers() async {
    final db = await database;
    final maps = await db.query('servers', orderBy: 'sort_order');
    return maps.map((m) => ServerConfig.fromMap(m)).toList();
  }

  Future<List<ServerConfig>> getServersByGroup(int groupId) async {
    final db = await database;
    final maps = await db.query('servers',
      where: 'group_id = ?', whereArgs: [groupId], orderBy: 'sort_order');
    return maps.map((m) => ServerConfig.fromMap(m)).toList();
  }

  Future<List<ServerConfig>> getUngroupedServers() async {
    final db = await database;
    final maps = await db.query('servers',
      where: 'group_id IS NULL', orderBy: 'sort_order');
    return maps.map((m) => ServerConfig.fromMap(m)).toList();
  }

  Future<int> insertServer(ServerConfig server) async {
    final db = await database;
    return db.insert('servers', server.toMap()..remove('id'));
  }

  Future<void> updateServer(ServerConfig server) async {
    final db = await database;
    await db.update('servers', server.toMap(), where: 'id = ?', whereArgs: [server.id]);
  }

  Future<void> deleteServer(int id) async {
    final db = await database;
    await db.delete('servers', where: 'id = ?', whereArgs: [id]);
  }
}
```

**Step 4: Commit**

```bash
git add lib/models/ lib/services/database_service.dart
git commit -m "feat: add data models and database service"
```

---

### Task 3: Credential Encryption Service

**Files:**
- Create: `lib/services/credential_service.dart`

**Step 1: Create CredentialService**

Uses flutter_secure_storage for storing encrypted credentials and master password hash.

```dart
// lib/services/credential_service.dart
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CredentialService {
  final _storage = const FlutterSecureStorage();

  // --- Master Password ---
  Future<bool> hasMasterPassword() async {
    return await _storage.containsKey(key: 'master_password_hash');
  }

  Future<void> setMasterPassword(String password) async {
    final hash = sha256.convert(utf8.encode(password)).toString();
    await _storage.write(key: 'master_password_hash', value: hash);
  }

  Future<bool> verifyMasterPassword(String password) async {
    final stored = await _storage.read(key: 'master_password_hash');
    if (stored == null) return false;
    final hash = sha256.convert(utf8.encode(password)).toString();
    return hash == stored;
  }

  // --- Server Credentials ---
  Future<void> savePassword(int serverId, String password) async {
    await _storage.write(key: 'server_${serverId}_password', value: password);
  }

  Future<String?> getPassword(int serverId) async {
    return await _storage.read(key: 'server_${serverId}_password');
  }

  Future<void> savePrivateKey(int serverId, String privateKey) async {
    await _storage.write(key: 'server_${serverId}_key', value: privateKey);
  }

  Future<String?> getPrivateKey(int serverId) async {
    return await _storage.read(key: 'server_${serverId}_key');
  }

  Future<void> deleteCredentials(int serverId) async {
    await _storage.delete(key: 'server_${serverId}_password');
    await _storage.delete(key: 'server_${serverId}_key');
  }
}
```

**Step 2: Commit**

```bash
git add lib/services/credential_service.dart
git commit -m "feat: add credential encryption service"
```

---

### Task 4: SSH Connection Service

**Files:**
- Create: `lib/services/ssh_service.dart`

**Step 1: Create SSHService**

```dart
// lib/services/ssh_service.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import '../models/server_config.dart';

class SSHService {
  SSHClient? _client;
  SSHSession? _shell;
  bool _isConnected = false;

  bool get isConnected => _isConnected;

  Future<void> connect({
    required ServerConfig server,
    String? password,
    String? privateKey,
    required void Function(String) onData,
    required void Function(String) onError,
    required void Function() onDone,
  }) async {
    try {
      final socket = await SSHSocket.connect(server.host, server.port,
        timeout: const Duration(seconds: 10));

      if (server.authType == AuthType.password && password != null) {
        _client = SSHClient(socket,
          username: server.username,
          onPasswordRequest: () => password,
        );
      } else if (server.authType == AuthType.key && privateKey != null) {
        _client = SSHClient(socket,
          username: server.username,
          identities: [...SSHKeyPair.fromPem(privateKey)],
        );
      } else {
        throw Exception('Missing credentials');
      }

      _shell = await _client!.shell(
        pty: SSHPtyConfig(
          width: 80,
          height: 24,
        ),
      );

      _isConnected = true;

      _shell!.stdout.listen(
        (data) => onData(utf8.decode(data, allowMalformed: true)),
        onError: (e) => onError(e.toString()),
        onDone: () {
          _isConnected = false;
          onDone();
        },
      );
    } catch (e) {
      _isConnected = false;
      onError(e.toString());
      rethrow;
    }
  }

  void write(String data) {
    _shell?.write(utf8.encode(data) as Uint8List);
  }

  void resizeTerminal(int width, int height) {
    _shell?.resizeTerminal(width, height);
  }

  void disconnect() {
    _shell?.close();
    _client?.close();
    _isConnected = false;
  }
}
```

**Step 2: Commit**

```bash
git add lib/services/ssh_service.dart
git commit -m "feat: add SSH connection service"
```

---

### Task 5: Riverpod Providers

**Files:**
- Create: `lib/providers/providers.dart`

**Step 1: Create providers**

```dart
// lib/providers/providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/database_service.dart';
import '../services/credential_service.dart';
import '../models/server_group.dart';
import '../models/server_config.dart';

// Service singletons
final databaseServiceProvider = Provider((ref) => DatabaseService());
final credentialServiceProvider = Provider((ref) => CredentialService());

// Auth state
final isUnlockedProvider = StateProvider<bool>((ref) => false);

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
final groupedServersProvider = FutureProvider<Map<int?, List<ServerConfig>>>((ref) async {
  final servers = await ref.watch(serversProvider.future);
  final map = <int?, List<ServerConfig>>{};
  for (final s in servers) {
    map.putIfAbsent(s.groupId, () => []).add(s);
  }
  return map;
});
```

**Step 2: Commit**

```bash
git add lib/providers/
git commit -m "feat: add Riverpod providers"
```

---

### Task 6: Master Password Screen

**Files:**
- Create: `lib/screens/lock_screen.dart`
- Modify: `lib/main.dart`

**Step 1: Create LockScreen**

```dart
// lib/screens/lock_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../services/credential_service.dart';
import 'server_list_screen.dart';

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});
  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final _controller = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isFirstTime = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkFirstTime();
  }

  Future<void> _checkFirstTime() async {
    final cred = ref.read(credentialServiceProvider);
    final has = await cred.hasMasterPassword();
    setState(() { _isFirstTime = !has; _loading = false; });
  }

  Future<void> _submit() async {
    final cred = ref.read(credentialServiceProvider);
    final pwd = _controller.text;

    if (_isFirstTime) {
      if (pwd.length < 4) {
        setState(() => _error = '密码至少4位');
        return;
      }
      if (pwd != _confirmController.text) {
        setState(() => _error = '两次输入不一致');
        return;
      }
      await cred.setMasterPassword(pwd);
    } else {
      final ok = await cred.verifyMasterPassword(pwd);
      if (!ok) {
        setState(() => _error = '密码错误');
        return;
      }
    }

    ref.read(isUnlockedProvider.notifier).state = true;
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ServerListScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: Text(_isFirstTime ? '设置主密码' : 'TomSSH')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.terminal, size: 64, color: Colors.green),
            const SizedBox(height: 24),
            TextField(
              controller: _controller,
              obscureText: true,
              decoration: InputDecoration(
                labelText: _isFirstTime ? '设置主密码' : '输入主密码',
                border: const OutlineInputBorder(),
                errorText: _error,
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_isFirstTime) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _confirmController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '确认密码',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submit(),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submit,
                child: Text(_isFirstTime ? '确认' : '解锁'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _confirmController.dispose();
    super.dispose();
  }
}
```

**Step 2: Update main.dart**

```dart
// lib/main.dart
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
```

**Step 3: Build and verify on device**

```bash
/home/tommy/flutter_3.38.5_stable/bin/flutter run
```
Expected: Lock screen displays, can set/verify master password.

**Step 4: Commit**

```bash
git add lib/screens/lock_screen.dart lib/main.dart
git commit -m "feat: add master password lock screen"
```

---

### Task 7: Server List Screen with Grouping

**Files:**
- Create: `lib/screens/server_list_screen.dart`

**Step 1: Create ServerListScreen**

Grouped server list with expandable groups. FAB to add server. Long press for edit/delete.

```dart
// lib/screens/server_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../models/server_group.dart';
import '../models/server_config.dart';
import 'server_edit_screen.dart';
import 'terminal_screen.dart';

class ServerListScreen extends ConsumerStatefulWidget {
  const ServerListScreen({super.key});
  @override
  ConsumerState<ServerListScreen> createState() => _ServerListScreenState();
}

class _ServerListScreenState extends ConsumerState<ServerListScreen> {
  final Set<int> _collapsedGroups = {};

  void _refresh() {
    ref.invalidate(groupsProvider);
    ref.invalidate(serversProvider);
    ref.invalidate(groupedServersProvider);
  }

  void _connectToServer(ServerConfig server) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TerminalScreen(server: server)),
    );
  }

  Future<void> _addGroup() async {
    final name = await _showInputDialog('新建分组', '分组名称');
    if (name != null && name.isNotEmpty) {
      final db = ref.read(databaseServiceProvider);
      await db.insertGroup(ServerGroup(name: name));
      _refresh();
    }
  }

  Future<void> _deleteServer(ServerConfig server) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除服务器'),
        content: Text('确定删除 "${server.name}"？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirm == true) {
      final db = ref.read(databaseServiceProvider);
      final cred = ref.read(credentialServiceProvider);
      await db.deleteServer(server.id!);
      await cred.deleteCredentials(server.id!);
      _refresh();
    }
  }

  Future<String?> _showInputDialog(String title, String hint) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(hintText: hint),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('确认')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(groupsProvider);
    final groupedAsync = ref.watch(groupedServersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('TomSSH'),
        actions: [
          IconButton(icon: const Icon(Icons.create_new_folder), onPressed: _addGroup, tooltip: '新建分组'),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(context,
            MaterialPageRoute(builder: (_) => const ServerEditScreen()));
          _refresh();
        },
        child: const Icon(Icons.add),
      ),
      body: groupsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('错误: $e')),
        data: (groups) => groupedAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('错误: $e')),
          data: (grouped) => _buildList(groups, grouped),
        ),
      ),
    );
  }

  Widget _buildList(List<ServerGroup> groups, Map<int?, List<ServerConfig>> grouped) {
    final ungrouped = grouped[null] ?? [];
    if (groups.isEmpty && ungrouped.isEmpty) {
      return const Center(child: Text('点击 + 添加服务器', style: TextStyle(fontSize: 16)));
    }

    return ListView(
      children: [
        for (final group in groups) ...[
          ListTile(
            leading: Icon(_collapsedGroups.contains(group.id)
              ? Icons.folder : Icons.folder_open),
            title: Text(group.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${(grouped[group.id] ?? []).length}', style: TextStyle(color: Colors.grey[400])),
                Icon(_collapsedGroups.contains(group.id)
                  ? Icons.expand_more : Icons.expand_less),
              ],
            ),
            onTap: () => setState(() {
              if (_collapsedGroups.contains(group.id)) {
                _collapsedGroups.remove(group.id);
              } else {
                _collapsedGroups.add(group.id!);
              }
            }),
            onLongPress: () => _showGroupActions(group),
          ),
          if (!_collapsedGroups.contains(group.id))
            for (final server in (grouped[group.id] ?? []))
              _buildServerTile(server),
        ],
        if (ungrouped.isNotEmpty) ...[
          if (groups.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(left: 16, top: 8),
              child: Text('未分组', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
          for (final server in ungrouped)
            _buildServerTile(server),
        ],
      ],
    );
  }

  Widget _buildServerTile(ServerConfig server) {
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 32, right: 16),
      leading: const Icon(Icons.computer, color: Colors.green),
      title: Text(server.name),
      subtitle: Text('${server.username}@${server.host}:${server.port}'),
      trailing: Icon(server.authType == AuthType.key ? Icons.key : Icons.password, size: 16),
      onTap: () => _connectToServer(server),
      onLongPress: () => _showServerActions(server),
    );
  }

  void _showGroupActions(ServerGroup group) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('重命名'),
            onTap: () async {
              Navigator.pop(ctx);
              final name = await _showInputDialog('重命名分组', group.name);
              if (name != null && name.isNotEmpty) {
                final db = ref.read(databaseServiceProvider);
                await db.updateGroup(group.copyWith(name: name));
                _refresh();
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text('删除分组', style: TextStyle(color: Colors.red)),
            onTap: () async {
              Navigator.pop(ctx);
              final db = ref.read(databaseServiceProvider);
              await db.deleteGroup(group.id!);
              _refresh();
            },
          ),
        ],
      ),
    );
  }

  void _showServerActions(ServerConfig server) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('编辑'),
            onTap: () async {
              Navigator.pop(ctx);
              await Navigator.push(context,
                MaterialPageRoute(builder: (_) => ServerEditScreen(server: server)));
              _refresh();
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text('删除', style: TextStyle(color: Colors.red)),
            onTap: () { Navigator.pop(ctx); _deleteServer(server); },
          ),
        ],
      ),
    );
  }
}
```

**Step 2: Verify build**

```bash
/home/tommy/flutter_3.38.5_stable/bin/flutter build apk --debug
```

**Step 3: Commit**

```bash
git add lib/screens/server_list_screen.dart
git commit -m "feat: add server list screen with grouping"
```

---

### Task 8: Server Edit Screen

**Files:**
- Create: `lib/screens/server_edit_screen.dart`

**Step 1: Create ServerEditScreen**

Form for adding/editing server config. Supports password and key auth. Allows selecting group and importing key files.

```dart
// lib/screens/server_edit_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/server_config.dart';
import '../models/server_group.dart';
import '../providers/providers.dart';

class ServerEditScreen extends ConsumerStatefulWidget {
  final ServerConfig? server;
  const ServerEditScreen({super.key, this.server});
  @override
  ConsumerState<ServerEditScreen> createState() => _ServerEditScreenState();
}

class _ServerEditScreenState extends ConsumerState<ServerEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _passwordCtrl;
  late final TextEditingController _keyCtrl;
  late AuthType _authType;
  int? _groupId;

  bool get _isEditing => widget.server != null;

  @override
  void initState() {
    super.initState();
    final s = widget.server;
    _nameCtrl = TextEditingController(text: s?.name ?? '');
    _hostCtrl = TextEditingController(text: s?.host ?? '');
    _portCtrl = TextEditingController(text: (s?.port ?? 22).toString());
    _userCtrl = TextEditingController(text: s?.username ?? '');
    _passwordCtrl = TextEditingController();
    _keyCtrl = TextEditingController();
    _authType = s?.authType ?? AuthType.password;
    _groupId = s?.groupId;
    if (_isEditing) _loadCredentials();
  }

  Future<void> _loadCredentials() async {
    final cred = ref.read(credentialServiceProvider);
    if (_authType == AuthType.password) {
      _passwordCtrl.text = await cred.getPassword(widget.server!.id!) ?? '';
    } else {
      _keyCtrl.text = await cred.getPrivateKey(widget.server!.id!) ?? '';
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final db = ref.read(databaseServiceProvider);
    final cred = ref.read(credentialServiceProvider);

    final config = ServerConfig(
      id: widget.server?.id,
      name: _nameCtrl.text,
      host: _hostCtrl.text,
      port: int.tryParse(_portCtrl.text) ?? 22,
      username: _userCtrl.text,
      authType: _authType,
      groupId: _groupId,
    );

    int serverId;
    if (_isEditing) {
      await db.updateServer(config);
      serverId = widget.server!.id!;
    } else {
      serverId = await db.insertServer(config);
    }

    if (_authType == AuthType.password) {
      await cred.savePassword(serverId, _passwordCtrl.text);
    } else {
      await cred.savePrivateKey(serverId, _keyCtrl.text);
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(groupsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? '编辑服务器' : '添加服务器')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: '名称', border: OutlineInputBorder()),
              validator: (v) => v == null || v.isEmpty ? '请输入名称' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _hostCtrl,
              decoration: const InputDecoration(labelText: '主机地址', border: OutlineInputBorder()),
              validator: (v) => v == null || v.isEmpty ? '请输入主机地址' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _portCtrl,
              decoration: const InputDecoration(labelText: '端口', border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _userCtrl,
              decoration: const InputDecoration(labelText: '用户名', border: OutlineInputBorder()),
              validator: (v) => v == null || v.isEmpty ? '请输入用户名' : null,
            ),
            const SizedBox(height: 12),
            groupsAsync.when(
              loading: () => const SizedBox(),
              error: (_, __) => const SizedBox(),
              data: (groups) => DropdownButtonFormField<int?>(
                value: _groupId,
                decoration: const InputDecoration(labelText: '分组', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem(value: null, child: Text('无分组')),
                  ...groups.map((g) => DropdownMenuItem(value: g.id, child: Text(g.name))),
                ],
                onChanged: (v) => setState(() => _groupId = v),
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<AuthType>(
              segments: const [
                ButtonSegment(value: AuthType.password, label: Text('密码'), icon: Icon(Icons.password)),
                ButtonSegment(value: AuthType.key, label: Text('密钥'), icon: Icon(Icons.key)),
              ],
              selected: {_authType},
              onSelectionChanged: (v) => setState(() => _authType = v.first),
            ),
            const SizedBox(height: 12),
            if (_authType == AuthType.password)
              TextFormField(
                controller: _passwordCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: '密码', border: OutlineInputBorder()),
                validator: (v) => v == null || v.isEmpty ? '请输入密码' : null,
              )
            else
              TextFormField(
                controller: _keyCtrl,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: '私钥内容',
                  hintText: '粘贴 PEM 格式的私钥',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v == null || v.isEmpty ? '请输入私钥' : null,
              ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: Text(_isEditing ? '保存' : '添加'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passwordCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }
}
```

**Step 2: Commit**

```bash
git add lib/screens/server_edit_screen.dart
git commit -m "feat: add server edit screen"
```

---

### Task 9: Terminal Screen with Multi-Tab Support

**Files:**
- Create: `lib/screens/terminal_screen.dart`

**Step 1: Create TerminalScreen**

Multi-tab terminal view. Each tab holds an SSH session connected to a server. Uses xterm widget for rendering.

```dart
// lib/screens/terminal_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';
import '../models/server_config.dart';
import '../providers/providers.dart';
import '../services/ssh_service.dart';

class _TerminalTab {
  final ServerConfig server;
  final Terminal terminal;
  final SSHService ssh;
  String status; // connecting, connected, disconnected, error

  _TerminalTab({
    required this.server,
    required this.terminal,
    required this.ssh,
    this.status = 'connecting',
  });
}

class TerminalScreen extends ConsumerStatefulWidget {
  final ServerConfig server;
  const TerminalScreen({super.key, required this.server});
  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen>
    with TickerProviderStateMixin {
  final List<_TerminalTab> _tabs = [];
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 0, vsync: this);
    _addTab(widget.server);
  }

  void _updateTabController() {
    _tabController.dispose();
    _tabController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: _tabs.length - 1,
    );
  }

  Future<void> _addTab(ServerConfig server) async {
    final terminal = Terminal(maxLines: 10000);
    final ssh = SSHService();
    final tab = _TerminalTab(server: server, terminal: terminal, ssh: ssh);

    terminal.onOutput = (data) {
      ssh.write(data);
    };

    terminal.onResize = (width, height, pixelWidth, pixelHeight) {
      ssh.resizeTerminal(width, height);
    };

    setState(() {
      _tabs.add(tab);
      _updateTabController();
    });

    _connect(tab);
  }

  Future<void> _connect(_TerminalTab tab) async {
    setState(() => tab.status = 'connecting');
    tab.terminal.write('正在连接 ${tab.server.host}:${tab.server.port}...\r\n');

    final cred = ref.read(credentialServiceProvider);
    String? password;
    String? privateKey;

    if (tab.server.authType == AuthType.password) {
      password = await cred.getPassword(tab.server.id!);
    } else {
      privateKey = await cred.getPrivateKey(tab.server.id!);
    }

    try {
      await tab.ssh.connect(
        server: tab.server,
        password: password,
        privateKey: privateKey,
        onData: (data) {
          tab.terminal.write(data);
        },
        onError: (error) {
          tab.terminal.write('\r\n[错误] $error\r\n');
          setState(() => tab.status = 'error');
        },
        onDone: () {
          tab.terminal.write('\r\n[连接已断开]\r\n');
          setState(() => tab.status = 'disconnected');
        },
      );
      setState(() => tab.status = 'connected');
    } catch (e) {
      tab.terminal.write('\r\n[连接失败] $e\r\n');
      setState(() => tab.status = 'error');
    }
  }

  void _closeTab(int index) {
    _tabs[index].ssh.disconnect();
    setState(() {
      _tabs.removeAt(index);
      if (_tabs.isEmpty) {
        Navigator.pop(context);
        return;
      }
      _updateTabController();
    });
  }

  Color _statusColor(String status) => switch (status) {
    'connected' => Colors.green,
    'connecting' => Colors.orange,
    _ => Colors.red,
  };

  @override
  Widget build(BuildContext context) {
    if (_tabs.isEmpty) return const SizedBox();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: _tabs.asMap().entries.map((e) {
            final tab = e.value;
            return Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 8, color: _statusColor(tab.status)),
                  const SizedBox(width: 6),
                  Text(tab.server.name),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () => _closeTab(e.key),
                    child: const Icon(Icons.close, size: 16),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新连接',
            onPressed: () {
              final tab = _tabs[_tabController.index];
              tab.ssh.disconnect();
              tab.terminal.write('\r\n[重新连接...]\r\n');
              _connect(tab);
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(),
        children: _tabs.map((tab) => TerminalView(
          tab.terminal,
          autofocus: true,
        )).toList(),
      ),
    );
  }

  @override
  void dispose() {
    for (final tab in _tabs) {
      tab.ssh.disconnect();
    }
    _tabController.dispose();
    super.dispose();
  }
}
```

**Step 2: Build and test on device**

```bash
/home/tommy/flutter_3.38.5_stable/bin/flutter run
```
Expected: Can navigate to terminal, see SSH connection, interact with shell.

**Step 3: Commit**

```bash
git add lib/screens/terminal_screen.dart
git commit -m "feat: add terminal screen with multi-tab SSH sessions"
```

---

### Task 10: Integration and Final Polish

**Step 1: Add import for AuthType in server_list_screen.dart**

Ensure all imports are correct across files.

**Step 2: Add INTERNET permission to AndroidManifest.xml**

In `android/app/src/main/AndroidManifest.xml`, ensure:
```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

**Step 3: Full build and device test**

```bash
/home/tommy/flutter_3.38.5_stable/bin/flutter run
```

Test flow:
1. Set master password on first launch
2. Add a server group
3. Add a server to the group
4. Connect to the server
5. Verify terminal works (ls, vim, etc.)
6. Open second tab from server list
7. Switch between tabs
8. Disconnect and reconnect

**Step 4: Final commit**

```bash
git add -A
git commit -m "feat: complete TomSSH app with multi-tab SSH terminal"
```
