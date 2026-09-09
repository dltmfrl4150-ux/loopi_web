import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

String createMediaBlobUrl(List<int> bytes, String mimeType) {
  return html.Url.createObjectUrlFromBlob(html.Blob([bytes], mimeType));
}

void revokeMediaBlobUrl(String? url) {
  if (url != null && url.startsWith('blob:')) {
    html.Url.revokeObjectUrl(url);
  }
}

/// Reads a same-origin `blob:` / `data:` URL. The Dart `http` client cannot.
Future<Uint8List?> readBlobUrlBytes(String url) async {
  try {
    if (url.startsWith('data:')) {
      final comma = url.indexOf(',');
      if (comma < 0) return null;
      final meta = url.substring(5, comma);
      final payload = url.substring(comma + 1);
      if (meta.contains(';base64')) {
        return Uint8List.fromList(base64Decode(payload));
      }
      return Uint8List.fromList(utf8.encode(Uri.decodeComponent(payload)));
    }
    final request = await html.HttpRequest.request(
      url,
      responseType: 'arraybuffer',
    );
    final response = request.response;
    if (response is ByteBuffer) {
      return Uint8List.view(response);
    }
  } catch (_) {}
  return null;
}