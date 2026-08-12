import 'package:dartssh2/dartssh2.dart' as dartssh2;
import 'package:flutter/foundation.dart';

/// A remote file or directory entry from SFTP listing.
class SftpEntry {
  final String filename;
  final String longname;
  final bool isDirectory;
  final bool isSymlink;
  final int size;
  final int permissions;
  final DateTime? modifiedAt;

  const SftpEntry({
    required this.filename,
    required this.longname,
    this.isDirectory = false,
    this.isSymlink = false,
    this.size = 0,
    this.permissions = 0,
    this.modifiedAt,
  });
}

/// Service wrapping dartssh2's SftpClient for remote file operations.
class SftpService extends ChangeNotifier {
  dartssh2.SftpClient? _sftp;
  bool _isConnected = false;
  String? _errorMessage;

  bool get isConnected => _isConnected;
  String? get errorMessage => _errorMessage;

  /// Initialize the SFTP session from an established SSHClient.
  Future<void> connect(dartssh2.SSHClient client) async {
    try {
      _sftp = await client.sftp();
      _isConnected = true;
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      _isConnected = false;
      _errorMessage = 'SFTP connect failed: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// List directory contents at [path].
  Future<List<SftpEntry>> listDirectory(String path) async {
    _ensureConnected();
    final items = await _sftp!.listdir(path);
    return items.map((item) {
      return SftpEntry(
        filename: item.filename,
        longname: item.longname,
        isDirectory: item.attr.isDirectory,
        isSymlink: item.attr.isSymbolicLink,
        size: item.attr.size ?? 0,
        permissions: item.attr.mode?.value ?? 0,
        modifiedAt: item.attr.modifyTime != null
            ? DateTime.fromMillisecondsSinceEpoch(item.attr.modifyTime! * 1000)
            : null,
      );
    }).toList();
  }

  /// Get file/directory attributes.
  Future<dartssh2.SftpFileAttrs> stat(String path) async {
    _ensureConnected();
    return await _sftp!.stat(path);
  }

  /// Create a directory.
  Future<void> createDirectory(String path) async {
    _ensureConnected();
    await _sftp!.mkdir(path);
  }

  /// Delete a file.
  Future<void> deleteFile(String path) async {
    _ensureConnected();
    await _sftp!.remove(path);
  }

  /// Remove an empty directory.
  Future<void> deleteDirectory(String path) async {
    _ensureConnected();
    await _sftp!.rmdir(path);
  }

  /// Rename a file or directory.
  Future<void> rename(String oldPath, String newPath) async {
    _ensureConnected();
    await _sftp!.rename(oldPath, newPath);
  }

  /// Read the contents of a file as bytes.
  Future<Uint8List> readFile(String path) async {
    _ensureConnected();
    final file = await _sftp!.open(path, mode: dartssh2.SftpFileOpenMode.read);
    final bytes = await file.readBytes();
    await file.close();
    return bytes;
  }

  /// Write bytes to a file.
  Future<void> writeFile(String path, Uint8List data) async {
    _ensureConnected();
    final file = await _sftp!.open(path, mode: dartssh2.SftpFileOpenMode.write);
    await file.writeBytes(data);
    await file.close();
  }

  /// Disconnect and clean up.
  Future<void> disconnect() async {
    try {
      _sftp?.close();
    } catch (_) {}
    _sftp = null;
    _isConnected = false;
    _errorMessage = null;
    notifyListeners();
  }

  void _ensureConnected() {
    if (_sftp == null) {
      throw StateError('SFTP not connected. Call connect() first.');
    }
  }
}
