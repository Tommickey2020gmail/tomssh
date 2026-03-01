import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:xterm/xterm.dart';

import '../models/server_config.dart';
import '../providers/providers.dart';
import '../services/ssh_service.dart';
import '../widgets/quick_commands_sheet.dart';
import '../widgets/virtual_keyboard.dart';

/// Holds the state for a single terminal tab/session.
class _TerminalTab {
  final ServerConfig server;
  final Terminal terminal;
  final SSHService ssh;
  String status;
  int reconnectAttempts;
  Timer? reconnectTimer;

  _TerminalTab({
    required this.server,
    required this.terminal,
    required this.ssh,
  })  : status = 'connecting',
        reconnectAttempts = 0;

  void cancelReconnect() {
    reconnectTimer?.cancel();
    reconnectTimer = null;
  }
}

/// Multi-tab SSH terminal screen.
///
/// Accepts an initial [ServerConfig] and automatically connects on launch.
/// Users can close tabs; when all tabs are closed, the screen pops.
class TerminalScreen extends ConsumerStatefulWidget {
  final ServerConfig server;

  const TerminalScreen({super.key, required this.server});

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final List<_TerminalTab> _tabs = [];
  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    _addTab(widget.server);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    for (final tab in _tabs) {
      tab.cancelReconnect();
      tab.ssh.disconnect(manual: true);
    }
    _tabController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App came back to foreground — check all tabs and reconnect if needed
      for (final tab in _tabs) {
        if (!tab.ssh.isConnected && tab.status != 'connecting') {
          tab.terminal.write('\r\n[App resumed, reconnecting...]\r\n');
          tab.reconnectAttempts = 0;
          _connectTab(tab);
        }
      }
    }
  }

  /// Rebuilds the [TabController] to match the current number of tabs.
  void _rebuildTabController({int? newIndex}) {
    final oldController = _tabController;
    _tabController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: newIndex?.clamp(0, _tabs.length - 1) ?? 0,
    );
    // Listen for tab changes so we can update the AppBar title.
    _tabController!.addListener(() {
      if (!_tabController!.indexIsChanging) {
        setState(() {});
      }
    });
    oldController?.dispose();
  }

  /// Adds a new tab for the given server and initiates the SSH connection.
  void _addTab(ServerConfig server) {
    final terminal = Terminal(maxLines: 10000);
    final ssh = SSHService();

    final tab = _TerminalTab(
      server: server,
      terminal: terminal,
      ssh: ssh,
    );

    setState(() {
      _tabs.add(tab);
      _rebuildTabController(newIndex: _tabs.length - 1);
    });

    // Wire terminal output (user keystrokes) to SSH.
    terminal.onOutput = (data) {
      ssh.write(data);
    };

    // Wire terminal resize events to SSH.
    terminal.onResize = (width, height, pixelWidth, pixelHeight) {
      ssh.resizeTerminal(width, height);
    };

    _connectTab(tab);
  }

  static const int _maxReconnectAttempts = 10;

  /// Connects (or reconnects) a single tab's SSH session.
  Future<void> _connectTab(_TerminalTab tab) async {
    tab.cancelReconnect();

    setState(() {
      tab.status = 'connecting';
    });

    tab.terminal.write('Connecting to ${tab.server.host}...\r\n');

    final credentials = ref.read(credentialServiceProvider);
    String? password;
    String? privateKey;

    try {
      if (tab.server.authType == AuthType.password) {
        password = await credentials.getPassword(tab.server.id!);
      } else {
        privateKey = await credentials.getPrivateKey(tab.server.id!);
      }

      await tab.ssh.connect(
        server: tab.server,
        password: password,
        privateKey: privateKey,
        onData: (data) {
          tab.terminal.write(data);
        },
        onError: (error) {
          tab.terminal.write('\r\nError: $error\r\n');
        },
        onDone: () {
          if (mounted) {
            setState(() {
              tab.status = 'disconnected';
            });
            tab.terminal.write('\r\n[Connection closed]\r\n');
            // Auto-reconnect if not manually disconnected
            if (!tab.ssh.wasManualDisconnect) {
              _scheduleReconnect(tab);
            }
          }
        },
      );

      if (mounted) {
        setState(() {
          tab.status = 'connected';
          tab.reconnectAttempts = 0; // Reset on successful connection
        });

        // Auto-attach to tmux session if enabled
        if (tab.server.useTmux) {
          // Short delay to let shell initialize
          await Future.delayed(const Duration(milliseconds: 500));
          final sessionName = 'tomssh_${tab.server.name.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')}';
          tab.ssh.write('tmux new-session -A -s $sessionName\n');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          tab.status = 'error';
        });
        tab.terminal.write('\r\nFailed to connect: $e\r\n');
        // Auto-reconnect on connection failure too
        if (!tab.ssh.wasManualDisconnect) {
          _scheduleReconnect(tab);
        }
      }
    }
  }

  /// Schedules an auto-reconnect with exponential backoff.
  void _scheduleReconnect(_TerminalTab tab) {
    if (!mounted) return;
    if (tab.reconnectAttempts >= _maxReconnectAttempts) {
      tab.terminal.write('[Auto-reconnect gave up after $_maxReconnectAttempts attempts. Tap refresh to reconnect manually.]\r\n');
      return;
    }

    tab.reconnectAttempts++;
    // Backoff: 2s, 4s, 6s, 8s, 10s, ... capped at 30s
    final delay = Duration(seconds: (tab.reconnectAttempts * 2).clamp(2, 30));
    tab.terminal.write('[Auto-reconnect in ${delay.inSeconds}s (attempt ${tab.reconnectAttempts}/$_maxReconnectAttempts)...]\r\n');

    tab.reconnectTimer = Timer(delay, () {
      if (mounted && !tab.ssh.wasManualDisconnect) {
        _connectTab(tab);
      }
    });
  }

  /// Closes the tab at [index], disconnecting its SSH session.
  void _closeTab(int index) {
    final tab = _tabs[index];
    tab.cancelReconnect();
    tab.ssh.disconnect(manual: true);

    setState(() {
      _tabs.removeAt(index);
    });

    if (_tabs.isEmpty) {
      Navigator.pop(context);
      return;
    }

    final newIndex = index >= _tabs.length ? _tabs.length - 1 : index;
    setState(() {
      _rebuildTabController(newIndex: newIndex);
    });
  }

  /// Shows the quick commands bottom sheet and sends selected command.
  /// Shows a multi-line text input dialog and sends content to terminal.
  void _showTextInput() async {
    if (_tabController == null || _tabs.isEmpty) return;
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('大段文本输入'),
        content: TextField(
          controller: controller,
          maxLines: 10,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '粘贴或输入多行文本...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('发送'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text != null && text.isNotEmpty && mounted) {
      final tab = _tabs[_tabController!.index];
      // Send line by line to simulate typing
      final lines = text.split('\n');
      for (var i = 0; i < lines.length; i++) {
        tab.ssh.write(lines[i]);
        if (i < lines.length - 1) {
          tab.ssh.write('\n');
        }
      }
    }
  }

  void _showQuickCommands() async {
    if (_tabController == null || _tabs.isEmpty) return;
    final db = ref.read(databaseServiceProvider);
    final command = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => QuickCommandsSheet(db: db),
    );
    if (command != null && mounted) {
      final tab = _tabs[_tabController!.index];
      tab.ssh.write('$command\n');
    }
  }

  /// Disconnects and reconnects the currently active tab.
  void _reconnectCurrentTab() {
    if (_tabController == null || _tabs.isEmpty) return;
    final tab = _tabs[_tabController!.index];
    tab.cancelReconnect();
    tab.reconnectAttempts = 0; // Reset attempts for manual reconnect
    tab.ssh.disconnect();
    tab.terminal.write('\r\nReconnecting...\r\n');
    _connectTab(tab);
  }

  /// Returns the status indicator color for a given status string.
  Color _statusColor(String status) {
    switch (status) {
      case 'connected':
        return Colors.green;
      case 'connecting':
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_tabs.isEmpty || _tabController == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_tabs[_tabController!.index].server.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_note),
            tooltip: '大段文本输入',
            onPressed: _showTextInput,
          ),
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: '常用命令',
            onPressed: _showQuickCommands,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reconnect',
            onPressed: _reconnectCurrentTab,
          ),
        ],
        bottom: _tabs.length > 1
            ? TabBar(
                controller: _tabController,
                isScrollable: true,
                tabs: List.generate(_tabs.length, (i) {
                  final tab = _tabs[i];
                  return Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: _statusColor(tab.status),
                            shape: BoxShape.circle,
                          ),
                        ),
                        Text(tab.server.name),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () => _closeTab(i),
                          borderRadius: BorderRadius.circular(12),
                          child: const Padding(
                            padding: EdgeInsets.all(4.0),
                            child: Icon(Icons.close, size: 16),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              )
            : null,
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: _tabs.map((tab) {
                return TerminalView(
                  tab.terminal,
                  autofocus: true,
                );
              }).toList(),
            ),
          ),
          VirtualKeyboard(terminal: _tabs[_tabController!.index].terminal),
        ],
      ),
    );
  }
}
