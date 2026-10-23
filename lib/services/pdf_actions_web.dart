import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

String _blobUrl(Uint8List bytes) {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/pdf'),
  );
  return web.URL.createObjectURL(blob);
}

Future<void> downloadPdfBytes(Uint8List bytes, String filename) async {
  final url = _blobUrl(bytes);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  web.document.body?.append(a);
  a.click();
  a.remove();
  web.URL.revokeObjectURL(url);
}

/// Opens the PDF in a new tab; use the viewer's print button from there.
Future<void> printPdfBytes(Uint8List bytes, String filename) async {
  web.window.open(_blobUrl(bytes), '_blank');
}