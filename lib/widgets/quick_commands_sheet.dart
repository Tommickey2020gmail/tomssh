import 'package:flutter/material.dart';
import '../models/quick_command.dart';
import '../services/database_service.dart';

/// Bottom sheet that shows quick commands list.
/// Tap a command to execute it; long press to edit/delete.
/// Returns the selected command string, or null if dismissed.
class QuickCommandsSheet extends StatefulWidget {
  final DatabaseService db;
  const QuickCommandsSheet({super.key, required this.db});

  @override
  State<QuickCommandsSheet> createState() => _QuickCommandsSheetState();
}

class _QuickCommandsSheetState extends State<QuickCommandsSheet> {
  List<QuickCommand> _commands = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cmds = await widget.db.getCommands();
    if (mounted) setState(() { _commands = cmds; _loading = false; });
  }

  Future<void> _showEditDialog({QuickCommand? existing}) async {
    final labelCtrl = TextEditingController(text: existing?.label ?? '');
    final cmdCtrl = TextEditingController(text: existing?.command ?? '');
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? '添加命令' : '编辑命令'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: labelCtrl,
                decoration: const InputDecoration(
                  labelText: '名称',
                  hintText: '例: 查看日志',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v == null || v.isEmpty ? '请输入名称' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: cmdCtrl,
                decoration: const InputDecoration(
                  labelText: '命令',
                  hintText: '例: tail -f /var/log/syslog',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
                validator: (v) => v == null || v.isEmpty ? '请输入命令' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              if (existing != null) {
                await widget.db.updateCommand(QuickCommand(
                  id: existing.id,
                  label: labelCtrl.text.trim(),
                  command: cmdCtrl.text.trim(),
                  sortOrder: existing.sortOrder,
                ));
              } else {
                await widget.db.insertCommand(QuickCommand(
                  label: labelCtrl.text.trim(),
                  command: cmdCtrl.text.trim(),
                ));
              }
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (saved == true) _load();
  }

  Future<void> _confirmDelete(QuickCommand cmd) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除命令'),
        content: Text('确定删除 "${cmd.label}"？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok == true) {
      await widget.db.deleteCommand(cmd.id!);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (ctx, scrollController) {
        return Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                children: [
                  const Icon(Icons.terminal, size: 20),
                  const SizedBox(width: 8),
                  const Text('常用命令',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () => _showEditDialog(),
                    tooltip: '添加命令',
                  ),
                ],
              ),
            ),
            const Divider(),
            // List
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _commands.isEmpty
                      ? const Center(child: Text('点击 + 添加常用命令'))
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: _commands.length,
                          itemBuilder: (ctx, i) {
                            final cmd = _commands[i];
                            return ListTile(
                              leading: const Icon(Icons.play_arrow, color: Colors.green),
                              title: Text(cmd.label),
                              subtitle: Text(cmd.command,
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    color: Colors.grey[400],
                                  )),
                              onTap: () => Navigator.pop(context, cmd.command),
                              onLongPress: () => _showActions(cmd),
                            );
                          },
                        ),
            ),
          ],
        );
      },
    );
  }

  void _showActions(QuickCommand cmd) {
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
                _showEditDialog(existing: cmd);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('删除', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDelete(cmd);
              },
            ),
          ],
        ),
      ),
    );
  }
}
