import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/server_config.dart';
import '../providers/providers.dart';

/// Screen for adding or editing a server configuration.
///
/// Pass an existing [ServerConfig] to edit it, or omit it to create a new one.
class ServerEditScreen extends ConsumerStatefulWidget {
  final ServerConfig? server;

  const ServerEditScreen({super.key, this.server});

  @override
  ConsumerState<ServerEditScreen> createState() => _ServerEditScreenState();
}

class _ServerEditScreenState extends ConsumerState<ServerEditScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _privateKeyController;

  late AuthType _authType;
  int? _groupId;
  bool _useTmux = false;
  bool _saving = false;
  bool _loadingCredentials = true;

  bool get _isEditing => widget.server != null;

  @override
  void initState() {
    super.initState();
    final s = widget.server;
    _nameController = TextEditingController(text: s?.name ?? '');
    _hostController = TextEditingController(text: s?.host ?? '');
    _portController = TextEditingController(text: '${s?.port ?? 22}');
    _usernameController = TextEditingController(text: s?.username ?? '');
    _passwordController = TextEditingController();
    _privateKeyController = TextEditingController();
    _authType = s?.authType ?? AuthType.password;
    _groupId = s?.groupId;
    _useTmux = s?.useTmux ?? false;

    if (_isEditing) {
      _loadCredentials();
    } else {
      _loadingCredentials = false;
    }
  }

  Future<void> _loadCredentials() async {
    final credentialService = ref.read(credentialServiceProvider);
    final serverId = widget.server!.id!;
    final password = await credentialService.getPassword(serverId);
    final privateKey = await credentialService.getPrivateKey(serverId);
    if (mounted) {
      setState(() {
        if (password != null) _passwordController.text = password;
        if (privateKey != null) _privateKeyController.text = privateKey;
        _loadingCredentials = false;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _privateKeyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      final db = ref.read(databaseServiceProvider);
      final cred = ref.read(credentialServiceProvider);

      final config = ServerConfig(
        id: widget.server?.id,
        name: _nameController.text.trim(),
        host: _hostController.text.trim(),
        port: int.parse(_portController.text.trim()),
        username: _usernameController.text.trim(),
        authType: _authType,
        groupId: _groupId,
        sortOrder: widget.server?.sortOrder ?? 0,
        useTmux: _useTmux,
      );

      int serverId;
      if (_isEditing) {
        await db.updateServer(config);
        serverId = config.id!;
      } else {
        serverId = await db.insertServer(config);
      }

      // Save credentials based on auth type.
      if (_authType == AuthType.password) {
        await cred.savePassword(serverId, _passwordController.text);
      } else {
        await cred.savePrivateKey(serverId, _privateKeyController.text);
      }

      // Invalidate cached server list so other screens refresh.
      ref.invalidate(serversProvider);
      ref.invalidate(groupedServersProvider);

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save server: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(groupsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Server' : 'Add Server'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      body: _loadingCredentials
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // --- Name ---
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      hintText: 'My Server',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Name is required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // --- Host ---
                  TextFormField(
                    controller: _hostController,
                    decoration: const InputDecoration(
                      labelText: 'Host',
                      hintText: '192.168.1.100 or example.com',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Host is required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // --- Port ---
                  TextFormField(
                    controller: _portController,
                    decoration: const InputDecoration(
                      labelText: 'Port',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textInputAction: TextInputAction.next,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Port is required';
                      }
                      final port = int.tryParse(v.trim());
                      if (port == null || port < 1 || port > 65535) {
                        return 'Port must be between 1 and 65535';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // --- Username ---
                  TextFormField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Username is required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // --- Group Dropdown ---
                  groupsAsync.when(
                    data: (groups) => DropdownButtonFormField<int?>(
                      initialValue: _groupId,
                      decoration: const InputDecoration(
                        labelText: 'Group',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('None'),
                        ),
                        ...groups.map(
                          (g) => DropdownMenuItem<int?>(
                            value: g.id,
                            child: Text(g.name),
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() => _groupId = v),
                    ),
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text('Failed to load groups: $e'),
                  ),
                  const SizedBox(height: 24),

                  // --- Auth Type Toggle ---
                  Text(
                    'Authentication',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('使用 tmux 保持会话'),
                    subtitle: const Text('断连后进程继续运行，重连自动恢复'),
                    value: _useTmux,
                    onChanged: (v) => setState(() => _useTmux = v),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<AuthType>(
                      segments: const [
                        ButtonSegment(
                          value: AuthType.password,
                          label: Text('Password'),
                          icon: Icon(Icons.password),
                        ),
                        ButtonSegment(
                          value: AuthType.key,
                          label: Text('Private Key'),
                          icon: Icon(Icons.key),
                        ),
                      ],
                      selected: {_authType},
                      onSelectionChanged: (selected) {
                        setState(() => _authType = selected.first);
                      },
                    ),
                  ),
                  const SizedBox(height: 16),

                  // --- Password or Private Key Field ---
                  if (_authType == AuthType.password)
                    TextFormField(
                      controller: _passwordController,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                      validator: (v) {
                        if (v == null || v.isEmpty) {
                          return 'Password is required';
                        }
                        return null;
                      },
                    )
                  else
                    TextFormField(
                      controller: _privateKeyController,
                      decoration: const InputDecoration(
                        labelText: 'Private Key',
                        hintText: '-----BEGIN OPENSSH PRIVATE KEY-----',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                      maxLines: 6,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Private key is required';
                        }
                        return null;
                      },
                    ),
                  const SizedBox(height: 32),

                  // --- Save Button ---
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save),
                    label: Text(_isEditing ? 'Update Server' : 'Add Server'),
                  ),
                ],
              ),
            ),
    );
  }
}
