import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/external_picker.dart';

class AudioImportResult {
  const AudioImportResult._({this.path, this.error});

  const AudioImportResult.success(String storedPath)
      : this._(path: storedPath);

  const AudioImportResult.cancelled() : this._();

  const AudioImportResult.failure(String message) : this._(error: message);

  final String? path;

  final String? error;

  bool get isCancelled => path == null && error == null;
}

class FileStorageService {
  static const String _backgroundsFolder = 'backgrounds';
  static const String _alarmAudioFolder = 'alarm_audio';

  static const List<String> supportedAudioExtensions = [
    'mp3', 'wav', 'm4a', 'aac', 'ogg', 'oga', 'opus', 'flac', 'amr',
  ];

  Future<Directory> _ensureFolder(String name) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, name));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<String> _importFile(String sourcePath, String folder) async {
    final dir = await _ensureFolder(folder);
    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}_${p.basename(sourcePath)}';
    final destination = p.join(dir.path, fileName);
    await File(sourcePath).copy(destination);
    return destination;
  }

  Future<String?> pickAndStoreBackgroundImage() async {
    try {
      final result = await ExternalPicker.run(
        () => FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
        ),
      );
      final files = result?.files ?? const [];
      final sourcePath = files.isEmpty ? null : files.first.path;
      if (sourcePath == null) return null;

      await _clearFolder(_backgroundsFolder);
      return await _importFile(sourcePath, _backgroundsFolder);
    } on PlatformException catch (error) {
      debugPrint('Background image pick failed: $error');
      return null;
    } on FileSystemException catch (error) {
      debugPrint('Background image import failed: $error');
      return null;
    } catch (error) {
      debugPrint('Background image pick failed unexpectedly: $error');
      return null;
    }
  }

  Future<AudioImportResult> pickAndStoreAlarmAudio() async {
    try {
      final result = await ExternalPicker.run(
        () => FilePicker.platform.pickFiles(
          // custom extensions show every file so stick to the audio type
          type: FileType.audio,
          allowMultiple: false,
        ),
      );
      if (result == null || result.files.isEmpty) {
        return const AudioImportResult.cancelled();
      }

      final sourcePath = result.files.first.path;
      if (sourcePath == null) {
        return const AudioImportResult.failure(
          'That file is not stored on this device. '
          'Please download it first, then pick it again.',
        );
      }

      final source = File(sourcePath);
      if (!await source.exists() || await source.length() == 0) {
        return const AudioImportResult.failure(
          'The selected file is empty or unreadable.',
        );
      }
      if (!await isLikelyAudioFile(source)) {
        return const AudioImportResult.failure(
          'That file does not look like a supported audio format. '
          'Please choose an MP3, WAV, M4A, AAC, OGG or FLAC file.',
        );
      }

      final storedPath = await _importFile(sourcePath, _alarmAudioFolder);
      return AudioImportResult.success(storedPath);
    } on PlatformException catch (error) {
      debugPrint('Audio pick failed: $error');
      return const AudioImportResult.failure(
        'The file picker could not be opened. Please try again.',
      );
    } on FileSystemException catch (error) {
      debugPrint('Audio import failed: $error');
      return const AudioImportResult.failure(
        'The selected audio file could not be copied into the app.',
      );
    } catch (error) {
      debugPrint('Audio pick failed unexpectedly: $error');
      return const AudioImportResult.failure(
        'Something went wrong while picking that file. Please try again.',
      );
    }
  }

  static String displayName(String storedPath) {
    final base = p.basenameWithoutExtension(storedPath);
    final match = RegExp(r'^\d{10,}_(.+)$').firstMatch(base);
    final name = (match == null ? base : match.group(1)!).trim();
    return name.isEmpty ? base : name;
  }

  @visibleForTesting
  static Future<bool> isLikelyAudioFile(File file) async {
    final extension =
        p.extension(file.path).replaceFirst('.', '').toLowerCase();
    if (!supportedAudioExtensions.contains(extension)) return false;

    final List<int> header;
    try {
      header = await file.openRead(0, 16).fold<List<int>>(
        <int>[],
        (bytes, chunk) => bytes..addAll(chunk),
      );
    } on FileSystemException {
      return false;
    }
    if (header.length < 4) return false;

    bool startsWith(List<int> signature, {int offset = 0}) {
      if (header.length < offset + signature.length) return false;
      for (var i = 0; i < signature.length; i++) {
        if (header[offset + i] != signature[i]) return false;
      }
      return true;
    }

    if (startsWith('ID3'.codeUnits)) return true;
    if (header[0] == 0xFF && (header[1] & 0xE0) == 0xE0) return true;
    if (startsWith('RIFF'.codeUnits) && startsWith('WAVE'.codeUnits, offset: 8)) {
      return true;
    }
    if (startsWith('OggS'.codeUnits)) return true;
    if (startsWith('fLaC'.codeUnits)) return true;
    if (startsWith('ftyp'.codeUnits, offset: 4)) return true;
    if (header[0] == 0xFF && (header[1] & 0xF6) == 0xF0) return true;
    if (startsWith('#!AMR'.codeUnits)) return true;

    return false;
  }

  Future<void> deleteBackgroundImage() => _clearFolder(_backgroundsFolder);

  Future<List<File>> listAlarmAudioFiles() async {
    final dir = await _ensureFolder(_alarmAudioFolder);
    final files = <File>[];
    await for (final entity in dir.list()) {
      if (entity is File) files.add(entity);
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  Future<int> pruneUnusedAlarmAudio(Set<String> referencedPaths) async {
    final referenced =
        referencedPaths.map((path) => p.normalize(path)).toSet();
    var removed = 0;
    for (final file in await listAlarmAudioFiles()) {
      if (referenced.contains(p.normalize(file.path))) continue;
      try {
        await file.delete();
        removed++;
      } on FileSystemException {
        // best effort
      }
    }
    return removed;
  }

  Future<void> deleteAlarmAudioFile(String path) async {
    try {
      await File(path).delete();
    } on FileSystemException {
      // best effort
    }
  }

  Future<int> clearTemporaryCache() async {
    var freed = 0;
    try {
      final tmp = await getTemporaryDirectory();
      await for (final entity in tmp.list()) {
        try {
          if (entity is File) {
            freed += await entity.length();
            await entity.delete();
          } else if (entity is Directory) {
            await entity.delete(recursive: true);
          }
        } on FileSystemException {
          // best effort
        }
      }
    } on FileSystemException {
      // best effort
    }
    return freed;
  }

  Future<void> _clearFolder(String folder) async {
    final dir = await _ensureFolder(folder);
    await for (final entity in dir.list()) {
      if (entity is File) {
        try {
          await entity.delete();
        } on FileSystemException {
          // best effort
        }
      }
    }
  }
}
