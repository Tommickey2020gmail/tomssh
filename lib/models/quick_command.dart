class QuickCommand {
  final int? id;
  final String label;
  final String command;
  final int sortOrder;

  QuickCommand({
    this.id,
    required this.label,
    required this.command,
    this.sortOrder = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'command': command,
        'sort_order': sortOrder,
      };

  factory QuickCommand.fromMap(Map<String, dynamic> map) => QuickCommand(
        id: map['id'] as int?,
        label: map['label'] as String,
        command: map['command'] as String,
        sortOrder: map['sort_order'] as int? ?? 0,
      );
}
