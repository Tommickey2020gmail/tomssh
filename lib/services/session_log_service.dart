import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Streams SSH session output to disk, rotating log files at 1MB.
class SessionLogService {
  final String serverName;
  IOSink? _sink;
  int _bytesWritten = 0;
  int _partNumber = 0;
  String? _logDir;
  String? _sessionTimestamp;
  static const int _maxBytes = 1024 * 1024; // 1MB

  SessionLogService(this.serverName);

  Future<void> init() async {
    final appDir = await getApplicationDocumentsDirectory();
    _logDir = '${appDir.path}/session_logs';
    await Directory(_logDir!).create(recursive: true);
    _sessionTimestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    _partNumber = 0;
    _bytesWritten = 0;
    await _openFile();
  }

  Future<void> _openFile() async {
    final safeName =
        serverName.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    final fileName = '${safeName}_${_sessionTimestamp}_p$_partNumber.log';
    final file = File('$_logDir/$fileName');
    _sink = file.openWrite(mode: FileMode.append);
  }

  /// Write data to the current log file. Rotates when exceeding 1MB.
  void write(String data) {
    if (_sink == null) return;
    _sink!.write(data);
    _bytesWritten += data.length;
    if (_bytesWritten >= _maxBytes) {
      _rotate();
    }
  }

  void _rotate() {
    _sink?.flush();
    _sink?.close();
    _partNumber++;
    _bytesWritten = 0;
    _openFile();
  }

  Future<void> close() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
  }
}
