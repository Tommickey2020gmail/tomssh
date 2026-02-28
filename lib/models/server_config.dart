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
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'username': username,
        'auth_type': authType.name,
        'group_id': groupId,
        'sort_order': sortOrder,
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
    int? id,
    String? name,
    String? host,
    int? port,
    String? username,
    AuthType? authType,
    int? groupId,
    int? sortOrder,
  }) =>
      ServerConfig(
        id: id ?? this.id,
        name: name ?? this.name,
        host: host ?? this.host,
        port: port ?? this.port,
        username: username ?? this.username,
        authType: authType ?? this.authType,
        groupId: groupId ?? this.groupId,
        sortOrder: sortOrder ?? this.sortOrder,
      );
}
