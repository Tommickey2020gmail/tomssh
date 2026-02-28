class ServerGroup {
  final int? id;
  final String name;
  final int sortOrder;

  ServerGroup({this.id, required this.name, this.sortOrder = 0});

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'sort_order': sortOrder,
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
