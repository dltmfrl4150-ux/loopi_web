import 'dart:html' as html;
import 'dart:typed_data';

Future<bool> downloadUrlAsFile({
  required String url,
  required String filename,
}) async {
  try {
    final anchor = html.AnchorElement(href: url)
      ..download = filename
      ..style.display = 'none'
      ..target = '_blank';
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> downloadBytesAsFile({
  required Uint8List bytes,
  required String filename,
  String mimeType = 'application/octet-stream',
}) async {
  try {
    final blob = html.Blob([bytes], mimeType);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final ok = await downloadUrlAsFile(url: url, filename: filename);
    // Delay revoke so the browser can start the download.
    Future<void>.delayed(const Duration(seconds: 30), () {
      html.Url.revokeObjectUrl(url);
    });
    return ok;
  } catch (_) {
    return false;
  }
}