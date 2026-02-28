import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../models/server_config.dart';
import '../providers/providers.dart';
import '../services/ssh_service.dart';

/// Holds the state for a single terminal tab/session.
class _TerminalTab {
  final ServerConfig server;
  final Terminal terminal;
  final SSHService ssh;
  String status;

  _TerminalTab({
    required this.server,
    required this.terminal,
    required this.ssh,
  }) : status = 'connecting';
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
    with TickerProviderStateMixin {
  final List<_TerminalTab> _tabs = [];
  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    _addTab(widget.server);
  }

  @override
  void dispose() {
    for (final tab in _tabs) {
      tab.ssh.disconnect();
    }
    _tabController?.dispose();
    super.dispose();
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

  /// Connects (or reconnects) a single tab's SSH session.
  Future<void> _connectTab(_TerminalTab tab) async {
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
          }
        },
      );

      if (mounted) {
        setState(() {
          tab.status = 'connected';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          tab.status = 'error';
        });
        tab.terminal.write('\r\nFailed to connect: $e\r\n');
      }
    }
  }

  /// Closes the tab at [index], disconnecting its SSH session.
  void _closeTab(int index) {
    final tab = _tabs[index];
    tab.ssh.disconnect();

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

  /// Disconnects and reconnects the currently active tab.
  void _reconnectCurrentTab() {
    if (_tabController == null || _tabs.isEmpty) return;
    final tab = _tabs[_tabController!.index];
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
      body: TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(),
        children: _tabs.map((tab) {
          return TerminalView(
            tab.terminal,
            autofocus: true,
          );
        }).toList(),
      ),
    );
  }
}
