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

  bool get isConnected => _isConnected;

  Future<void> connect({
    required ServerConfig server,
    String? password,
    String? privateKey,
    required void Function(String) onData,
    required void Function(String) onError,
    required void Function() onDone,
  }) async {
    try {
      final socket = await SSHSocket.connect(server.host, server.port,
          timeout: const Duration(seconds: 10));

      if (server.authType == AuthType.password && password != null) {
        _client = SSHClient(socket,
          username: server.username,
          onPasswordRequest: () => password,
        );
      } else if (server.authType == AuthType.key && privateKey != null) {
        _client = SSHClient(socket,
          username: server.username,
          identities: [...SSHKeyPair.fromPem(privateKey)],
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

  void disconnect() {
    _stdoutSubscription?.cancel();
    _stdoutSubscription = null;
    _shell?.close();
    _client?.close();
    _isConnected = false;
  }
}
