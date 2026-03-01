import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import '../models/server_config.dart';

class SSHService {
  SSHClient? _client;
  SSHSession? _shell;
  StreamSubscription? _stdoutSubscription;
  bool _isConnected = false;
  bool _manualDisconnect = false;

  bool get isConnected => _isConnected;

  Future<void> connect({
    required ServerConfig server,
    String? password,
    String? privateKey,
    required void Function(String) onData,
    required void Function(String) onError,
    required void Function() onDone,
  }) async {
    _manualDisconnect = false;
    try {
      final socket = await SSHSocket.connect(server.host, server.port,
          timeout: const Duration(seconds: 15));

      if (server.authType == AuthType.password && password != null) {
        _client = SSHClient(socket,
          username: server.username,
          onPasswordRequest: () => password,
          keepAliveInterval: const Duration(seconds: 5),
        );
      } else if (server.authType == AuthType.key && privateKey != null) {
        _client = SSHClient(socket,
          username: server.username,
          identities: [...SSHKeyPair.fromPem(privateKey)],
          keepAliveInterval: const Duration(seconds: 5),
        );
      } else {
        throw Exception('Missing credentials');
      }

      _shell = await _client!.shell(
        pty: SSHPtyConfig(
          width: 80,
          height: 24,
        ),
      );

      _isConnected = true;

      _stdoutSubscription?.cancel();
      _stdoutSubscription = _shell!.stdout.listen(
        (data) => onData(utf8.decode(data, allowMalformed: true)),
        onError: (e) => onError(e.toString()),
        onDone: () {
          _isConnected = false;
          onDone();
        },
      );
    } catch (e) {
      _isConnected = false;
      onError(e.toString());
      rethrow;
    }
  }

  void write(String data) {
    _shell?.write(Uint8List.fromList(utf8.encode(data)));
  }

  void resizeTerminal(int width, int height) {
    _shell?.resizeTerminal(width, height);
  }

  /// If [manual] is true, auto-reconnect will not trigger.
  void disconnect({bool manual = false}) {
    _manualDisconnect = manual;
    _stdoutSubscription?.cancel();
    _stdoutSubscription = null;
    _shell?.close();
    _client?.close();
    _isConnected = false;
  }

  /// Whether the last disconnect was triggered manually by the user.
  bool get wasManualDisconnect => _manualDisconnect;
}
