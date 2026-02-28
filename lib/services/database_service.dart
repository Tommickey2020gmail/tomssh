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
}
