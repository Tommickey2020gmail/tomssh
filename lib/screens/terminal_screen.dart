import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:xterm/xterm.dart';

import '../models/server_config.dart';
import '../providers/providers.dart';
import '../services/session_log_service.dart';
import '../services/ssh_service.dart';
import '../widgets/quick_commands_sheet.dart';
import '../widgets/virtual_keyboard.dart';

/// Holds the state for a single terminal tab/session.
class _TerminalTab {
  final ServerConfig server;
  final Terminal terminal;
  final SSHService ssh;
  final SessionLogService logService;
  final KeyboardModifiers modifiers = KeyboardModifiers();
  String status;
  int reconnectAttempts;
  Timer? reconnectTimer;

  _TerminalTab({
    required this.server,
    required this.terminal,
    required this.ssh,
    required this.logService,
  })  : status = 'connecting',
        reconnectAttempts = 0;

  void cancelReconnect() {
    reconnectTimer?.cancel();
    reconnectTimer = null;
  }

  Future<void> closeLog() async {
    await logService.close();
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
      tab.closeLog();
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
    final terminal = Terminal(maxLines: 50000);
    final ssh = SSHService();
    final logService = SessionLogService(server.name);

    final tab = _TerminalTab(
      server: server,
      terminal: terminal,
      ssh: ssh,
      logService: logService,
    );

    // Init log service asynchronously.
    logService.init();

    setState(() {
      _tabs.add(tab);
      _rebuildTabController(newIndex: _tabs.length - 1);
    });

    // Wire terminal output (user keystrokes) to SSH.
    // Apply virtual keyboard modifiers (Ctrl/Alt) to system keyboard input.
    terminal.onOutput = (data) {
      final modified = tab.modifiers.applyModifiers(data);
      ssh.write(modified ?? data);
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
          tab.logService.write(data);
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
    tab.closeLog();

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

  /// Shows the terminal buffer history in a full-screen dialog.
  void _showHistory() {
    if (_tabs.isEmpty) return;
    final tab = _tabs[_safeIndex];
    final text = tab.terminal.buffer.getText();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => _HistoryViewer(text: text, title: tab.server.name),
      ),
    );
  }

  /// Shows the quick commands bottom sheet and sends selected command.
  /// Shows a multi-line text input bottom sheet and sends content to terminal.
  void _showTextInput() async {
    if (_tabs.isEmpty) return;
    final controller = TextEditingController();
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
        return AnimatedPadding(
          duration: const Duration(milliseconds: 100),
          padding: EdgeInsets.only(
            bottom: bottomInset,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Text('大段文本输入',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                    },
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      final value = controller.text;
                      Navigator.of(ctx).pop(value);
                    },
                    child: const Text('发送'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                maxLines: 8,
                minLines: 3,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '粘贴或输入多行文本...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
    // Dispose after a frame to avoid race with sheet exit animation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });
    if (text != null && text.isNotEmpty && mounted && _tabs.isNotEmpty) {
      final tab = _tabs[_safeIndex];
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
    if (_tabs.isEmpty) return;
    final db = ref.read(databaseServiceProvider);
    final command = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => QuickCommandsSheet(db: db),
    );
    if (command != null && mounted && _tabs.isNotEmpty) {
      final tab = _tabs[_safeIndex];
      tab.ssh.write('$command\n');
    }
  }

  /// Disconnects and reconnects the currently active tab.
  void _reconnectCurrentTab() {
    if (_tabs.isEmpty) return;
    final tab = _tabs[_safeIndex];
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

  /// Safe accessor for the current tab index.
  int get _safeIndex {
    if (_tabController == null || _tabs.isEmpty) return 0;
    return _tabController!.index.clamp(0, _tabs.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    if (_tabs.isEmpty || _tabController == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final currentIndex = _safeIndex;
    final currentTab = _tabs[currentIndex];

    return Scaffold(
      appBar: AppBar(
        title: Text(currentTab.server.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: '历史记录',
            onPressed: _showHistory,
          ),
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
                return _TouchScrollableTerminal(terminal: tab.terminal);
              }).toList(),
            ),
          ),
          VirtualKeyboard(terminal: currentTab.terminal, modifiers: currentTab.modifiers),
        ],
      ),
    );
  }
}

/// Wraps [TerminalView] with a [Listener] that drives the ScrollController
/// from touch drag gestures, working around xterm's gesture arena blocking
/// touch scrolling on mobile.
class _TouchScrollableTerminal extends StatefulWidget {
  final Terminal terminal;
  const _TouchScrollableTerminal({required this.terminal});

  @override
  State<_TouchScrollableTerminal> createState() =>
      _TouchScrollableTerminalState();
}

class _TouchScrollableTerminalState extends State<_TouchScrollableTerminal> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final newOffset = (pos.pixels - details.delta.dy)
        .clamp(pos.minScrollExtent, pos.maxScrollExtent);
    if (newOffset != pos.pixels) {
      _scrollController.jumpTo(newOffset);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      gestures: <Type, GestureRecognizerFactory>{
        VerticalDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<VerticalDragGestureRecognizer>(
          () => VerticalDragGestureRecognizer()
            ..supportedDevices = {ui.PointerDeviceKind.touch},
          (VerticalDragGestureRecognizer instance) {
            instance.onUpdate = _onVerticalDragUpdate;
          },
        ),
      },
      child: TerminalView(
        widget.terminal,
        autofocus: true,
        simulateScroll: false,
        scrollController: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
    );
  }
}

/// Full-screen viewer for terminal buffer history with search support.
class _HistoryViewer extends StatefulWidget {
  final String text;
  final String title;
  const _HistoryViewer({required this.text, required this.title});

  @override
  State<_HistoryViewer> createState() => _HistoryViewerState();
}

class _HistoryViewerState extends State<_HistoryViewer> {
  final ScrollController _scrollController = ScrollController();
  bool _searching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: '搜索...',
                  hintStyle: TextStyle(color: Colors.white54),
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              )
            : Text('${widget.title} - 历史记录'),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                if (_searching) {
                  _searchController.clear();
                  _searchQuery = '';
                }
                _searching = !_searching;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.vertical_align_bottom),
            tooltip: '跳到底部',
            onPressed: () {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_scrollController.hasClients) {
                  _scrollController.jumpTo(
                    _scrollController.position.maxScrollExtent,
                  );
                }
              });
            },
          ),
        ],
      ),
      body: _buildContent(),
    );
  }

  Widget _buildContent() {
    final lines = widget.text.split('\n');

    if (_searchQuery.isEmpty) {
      return ListView.builder(
        controller: _scrollController,
        itemCount: lines.length,
        padding: const EdgeInsets.all(8),
        itemBuilder: (ctx, i) {
          return Text(
            lines[i],
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.3,
            ),
          );
        },
      );
    }

    // Filter lines that match the search query
    final queryLower = _searchQuery.toLowerCase();
    final matched = <int>[];
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].toLowerCase().contains(queryLower)) {
        matched.add(i);
      }
    }

    if (matched.isEmpty) {
      return const Center(child: Text('没有找到匹配内容'));
    }

    return ListView.builder(
      controller: _scrollController,
      itemCount: matched.length,
      padding: const EdgeInsets.all(8),
      itemBuilder: (ctx, i) {
        final lineIndex = matched[i];
        final line = lines[lineIndex];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 48,
                child: Text(
                  '${lineIndex + 1}',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
              ),
              Expanded(
                child: _highlightText(line, _searchQuery),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _highlightText(String text, String query) {
    if (query.isEmpty) {
      return Text(
        text,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.3),
      );
    }

    final spans = <TextSpan>[];
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    var start = 0;

    while (true) {
      final idx = lowerText.indexOf(lowerQuery, start);
      if (idx == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx)));
      }
      spans.add(TextSpan(
        text: text.substring(idx, idx + query.length),
        style: const TextStyle(
          backgroundColor: Colors.yellow,
          color: Colors.black,
        ),
      ));
      start = idx + query.length;
    }

    return RichText(
      text: TextSpan(
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.3),
        children: spans,
      ),
    );
  }
}
