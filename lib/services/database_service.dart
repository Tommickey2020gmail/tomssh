import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/server_group.dart';
import '../models/server_config.dart';
import '../models/quick_command.dart';

class DatabaseService {
  static Database? _database;

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'tomssh.db');
    return openDatabase(path, version: 2,
        onCreate: _onCreate, onUpgrade: _onUpgrade);
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
    await _createCommandsTable(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createCommandsTable(db);
    }
  }

  Future<void> _createCommandsTable(Database db) async {
    await db.execute('''
      CREATE TABLE commands (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        label TEXT NOT NULL,
        command TEXT NOT NULL,
        sort_order INTEGER DEFAULT 0
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
    await db.update('groups', group.toMap(),
        where: 'id = ?', whereArgs: [group.id]);
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
    await db.update('servers', server.toMap(),
        where: 'id = ?', whereArgs: [server.id]);
  }

  Future<void> deleteServer(int id) async {
    final db = await database;
    await db.delete('servers', where: 'id = ?', whereArgs: [id]);
  }

  // --- Quick Commands ---
  Future<List<QuickCommand>> getCommands() async {
    final db = await database;
    final maps = await db.query('commands', orderBy: 'sort_order');
    return maps.map((m) => QuickCommand.fromMap(m)).toList();
  }

  Future<int> insertCommand(QuickCommand cmd) async {
    final db = await database;
    return db.insert('commands', cmd.toMap()..remove('id'));
  }

  Future<void> updateCommand(QuickCommand cmd) async {
    final db = await database;
    await db.update('commands', cmd.toMap(),
        where: 'id = ?', whereArgs: [cmd.id]);
  }

  Future<void> deleteCommand(int id) async {
    final db = await database;
    await db.delete('commands', where: 'id = ?', whereArgs: [id]);
  }
}
