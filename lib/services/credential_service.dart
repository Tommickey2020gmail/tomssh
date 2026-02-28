// lib/services/credential_service.dart
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CredentialService {
  final _storage = const FlutterSecureStorage();

  // --- Master Password ---
  Future<bool> hasMasterPassword() async {
    return await _storage.containsKey(key: 'master_password_hash');
  }

  Future<void> setMasterPassword(String password) async {
    final hash = sha256.convert(utf8.encode(password)).toString();
    await _storage.write(key: 'master_password_hash', value: hash);
  }

  Future<bool> verifyMasterPassword(String password) async {
    final stored = await _storage.read(key: 'master_password_hash');
    if (stored == null) return false;
    final hash = sha256.convert(utf8.encode(password)).toString();
    return hash == stored;
  }

  // --- Server Credentials ---
  Future<void> savePassword(int serverId, String password) async {
    await _storage.write(key: 'server_${serverId}_password', value: password);
  }

  Future<String?> getPassword(int serverId) async {
    return await _storage.read(key: 'server_${serverId}_password');
  }

  Future<void> savePrivateKey(int serverId, String privateKey) async {
    await _storage.write(key: 'server_${serverId}_key', value: privateKey);
  }

  Future<String?> getPrivateKey(int serverId) async {
    return await _storage.read(key: 'server_${serverId}_key');
  }

  Future<void> deleteCredentials(int serverId) async {
    await _storage.delete(key: 'server_${serverId}_password');
    await _storage.delete(key: 'server_${serverId}_key');
  }
}
