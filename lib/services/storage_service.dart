import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../utils/media_blob.dart';
import '../utils/media_limits.dart';
import 'auth_service.dart';

class StorageService {
  static bool get _ready => FirebaseBootstrap.initialized;

  static bool _isRemoteHttp(String path) {
    return (path.startsWith('https://') || path.startsWith('http://')) &&
        !path.contains('localhost') &&
        !path.contains('127.0.0.1');
  }

  static Future<Uint8List?> readMediaBytes({
    String? path,
    List<int>? bytes,
  }) async {
    if (bytes != null && bytes.isNotEmpty) {
      return Uint8List.fromList(bytes);
    }
    if (path == null) return null;
    final value = path.trim();
    if (value.isEmpty) return null;
    final lower = value.toLowerCase();
    if (lower.contains('virtual') || lower.contains('dummy')) return null;
    try {
      if (value.startsWith('blob:') || value.startsWith('data:')) {
        final fromBlob = await readBlobUrlBytes(value);
        if (fromBlob != null && fromBlob.isNotEmpty) {
          debugPrint('[LOOPI] readMediaBytes blob/data ok bytes=${fromBlob.lengthInBytes}');
          return fromBlob;
        }
        debugPrint('[LOOPI] readMediaBytes blob/data empty for $value');
        return null;
      }
      if (value.startsWith('http://') || value.startsWith('https://')) {
        final response = await http.get(Uri.parse(value));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return response.bodyBytes;
        }
        debugPrint('[LOOPI] readMediaBytes http ${response.statusCode} for $value');
        return null;
      }
      if (!kIsWeb) {
        return await File(value).readAsBytes();
      }
    } catch (error) {
      debugPrint('StorageService.readMediaBytes error: $error');
    }
    return null;
  }

  static ({String ext, String mime}) detectUploadType({
    required Uint8List bytes,
    required bool audio,
    String? path,
  }) {
    if (bytes.length >= 12) {
      final riff = bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46;
      if (riff) return (ext: 'wav', mime: 'audio/wav');
      final webm = bytes[0] == 0x1A && bytes[1] == 0x45 && bytes[2] == 0xDF && bytes[3] == 0xA3;
      if (webm) {
        return audio
            ? (ext: 'webm', mime: 'audio/webm')
            : (ext: 'webm', mime: 'video/webm');
      }
      final ftyp = bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70;
      if (ftyp) {
        return audio ? (ext: 'm4a', mime: 'audio/mp4') : (ext: 'mp4', mime: 'video/mp4');
      }
    }
    final lower = (path ?? '').toLowerCase();
    if (lower.contains('.wav')) return (ext: 'wav', mime: 'audio/wav');
    if (lower.contains('.webm')) {
      return audio ? (ext: 'webm', mime: 'audio/webm') : (ext: 'webm', mime: 'video/webm');
    }
    if (lower.contains('.m4a') || lower.contains('.aac')) {
      return (ext: 'm4a', mime: 'audio/mp4');
    }
    return audio ? (ext: 'm4a', mime: 'audio/mp4') : (ext: 'mp4', mime: 'video/mp4');
  }

  static Future<String?> uploadPracticeRecording({
    required String userId,
    required String resultId,
    String? path,
    List<int>? bytes,
    bool audio = false,
  }) async {
    if (path != null && _isRemoteHttp(path.trim())) {
      return path.trim();
    }
    final data = await readMediaBytes(path: path, bytes: bytes);
    if (data == null || data.isEmpty) {
      debugPrint(
        '[LOOPI] uploadPracticeRecording aborted: no bytes path=$path hasInlineBytes=${bytes != null && bytes.isNotEmpty}',
      );
      return null;
    }
    if (!_ready) {
      debugPrint('[LOOPI] uploadPracticeRecording aborted: Firebase Storage not initialized');
      return null;
    }
    if (data.lengthInBytes >= kMaxStorageUploadBytes) {
      debugPrint(
        'StorageService.uploadPracticeRecording rejected: ${data.lengthInBytes} bytes exceeds $kMaxStorageUploadBytes',
      );
      return null;
    }
    final type = detectUploadType(bytes: data, audio: audio, path: path);
    try {
      final ref = FirebaseStorage.instance.ref('showcase/$userId/$resultId.${type.ext}');
      await ref.putData(data, SettableMetadata(contentType: type.mime));
      final url = await ref.getDownloadURL();
      debugPrint(
        '[LOOPI] uploadPracticeRecording ok user=$userId result=$resultId mime=${type.mime} bytes=${data.lengthInBytes} url=$url',
      );
      return url;
    } catch (error) {
      debugPrint('StorageService.uploadPracticeRecording error: $error');
      return null;
    }
  }

  static const int kMaxAvatarUploadBytes = 50 * 1024;

  static Future<String?> uploadAvatar({
    required String userId,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    if (!_ready || userId.isEmpty || bytes.isEmpty) return null;
    if (bytes.lengthInBytes > kMaxAvatarUploadBytes * 4) {
      debugPrint('StorageService.uploadAvatar rejected: ${bytes.lengthInBytes} bytes');
      return null;
    }
    try {
      final ref = FirebaseStorage.instance.ref('avatars/$userId/avatar.jpg');
      await ref.putData(bytes, SettableMetadata(contentType: contentType));
      return await ref.getDownloadURL();
    } catch (error) {
      debugPrint('StorageService.uploadAvatar error: $error');
      return null;
    }
  }
}
