import 'dart:typed_data';

/// Triggers a file download. No-op on non-web platforms.
Future<bool> downloadUrlAsFile({
  required String url,
  required String filename,
}) async {
  return false;
}

/// Triggers a file download from bytes. No-op on non-web platforms.
Future<bool> downloadBytesAsFile({
  required Uint8List bytes,
  required String filename,
  String mimeType = 'application/octet-stream',
}) async {
  return false;
}